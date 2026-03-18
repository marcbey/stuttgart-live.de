require "json"

module Importing
  module LlmEnrichment
    class Importer
      RUN_STALE_AFTER = 45.minutes
      RUN_HEARTBEAT_STALE_AFTER = 10.minutes
      BATCH_SIZE = 25
      PROMPT_VERSION = "v1"
      OUTPUT_SCHEMA_NAME = "event_llm_enrichment_batch".freeze
      OUTPUT_ITEMS_KEY = "events".freeze

      Item = Data.define(:event_id, :artist_name, :event_name, :venue) do
        def as_json(*)
          {
            event_id: event_id,
            artist_name: artist_name,
            event_name: event_name,
            venue: venue
          }
        end
      end

      Result = Data.define(:selected_count, :skipped_count, :enriched_count, :batches_count, :merge_run_id, :model, :canceled)

      def initialize(run:, client: OpenAi::ResponsesClient.new, logger: Importing::Logging.logger)
        @run = run
        @client = client
        @logger = logger
      end

      def call
        merge_run = latest_successful_merge_run
        raise Error, "Kein erfolgreicher Merge-Lauf gefunden." if merge_run.blank?

        selected_events = events_for_merge_run(merge_run)
        skipped_count = already_enriched_count(selected_events)
        pending_events = selected_events.where.missing(:llm_enrichment).order(:id).to_a
        batches = pending_events.each_slice(BATCH_SIZE).to_a
        enriched_count = 0
        batches_processed = 0

        logger.info("[LlmEnrichmentImporter] run_id=#{run.id} started merge_run_id=#{merge_run.id} selected=#{selected_events.count} skipped=#{skipped_count} batches=#{batches.count}")

        update_run_progress!(
          selected_count: selected_events.count,
          skipped_count: skipped_count,
          enriched_count: enriched_count,
          batches_count: batches.count,
          batches_processed: batches_processed,
          "merge_run_id" => merge_run.id,
          "batch_size" => BATCH_SIZE,
          "model" => client_model
        )

        batches.each_with_index do |batch_events, index|
          if stop_requested?
            logger.info("[LlmEnrichmentImporter] run_id=#{run.id} stop requested before batch=#{index + 1}")
            return canceled_result(selected_events:, skipped_count:, enriched_count:, batches_count: batches.count, merge_run:)
          end

          touch_run_heartbeat!("current_batch" => index + 1)
          logger.info("[LlmEnrichmentImporter] run_id=#{run.id} requesting batch=#{index + 1}/#{batches.count} size=#{batch_events.size}")

          items = batch_events.map { |event| item_for(event) }
          response = client.create!(input: request_input(items), text_format: output_format)
          payload = extract_payload!(response)
          enriched_count += persist_batch!(payload:, run:, batch_event_ids: batch_events.map(&:id))
          batches_processed += 1
          logger.info("[LlmEnrichmentImporter] run_id=#{run.id} completed batch=#{batches_processed}/#{batches.count} enriched_total=#{enriched_count}")

          update_run_progress!(
            selected_count: selected_events.count,
            skipped_count: skipped_count,
            enriched_count: enriched_count,
            batches_count: batches.count,
            batches_processed: batches_processed,
            "current_batch" => batches_processed
          )
        end

        Result.new(
          selected_count: selected_events.count,
          skipped_count: skipped_count,
          enriched_count: enriched_count,
          batches_count: batches.count,
          merge_run_id: merge_run.id,
          model: client_model,
          canceled: false
        )
      rescue StandardError => e
        logger.error("[LlmEnrichmentImporter] run_id=#{run.id} failed: #{e.class}: #{e.message}")
        raise
      end

      private

      Error = Class.new(StandardError)

      attr_reader :client, :logger, :run

      def latest_successful_merge_run
        ImportRun.where(source_type: "merge", status: "succeeded").order(finished_at: :desc, id: :desc).first
      end

      def events_for_merge_run(merge_run)
        Event
          .joins(:event_change_logs)
          .where(event_change_logs: { action: "merged_create" })
          .where("event_change_logs.metadata ->> 'merge_run_id' = ?", merge_run.id.to_s)
          .distinct
      end

      def already_enriched_count(scope)
        scope.joins(:llm_enrichment).distinct.count
      end

      def item_for(event)
        Item.new(
          event_id: event.id,
          artist_name: event.artist_name.to_s,
          event_name: event.title.to_s,
          venue: event.venue.to_s
        )
      end

      def request_input(items)
        # <<~TEXT
        #   Du erhältst Event-Daten als JSON-Liste. Recherchiere pro Event sinnvolle Zusatzinformationen und gib ausschließlich JSON zurück, das exakt dem Schema entspricht.

        #   Regeln:
        #   - Nutze dieselbe event_id wie im Input.
        #   - genre ist ein Array kurzer Genre-Strings.
        #   - venue muss als String zurückgegeben werden.
        #   - Gib ein JSON-Objekt mit dem Schlüssel "#{OUTPUT_ITEMS_KEY}" zurück.
        #   - Wenn ein Link oder Text nicht verlässlich ermittelbar ist, gib null zurück.
        #   - Erfinde keine Fakten.

        #   Input JSON:
        #   #{JSON.pretty_generate(items.map(&:as_json))}
        # TEXT

        <<~TEXT
          Ermittle zu den Events aus `Input` die fehlenden Felder

          - `genre`
          - `youtube_link`
          - `instagram_link`
          - `hompage_link`
          - `facebook_link`
          - `artist_description`
          - `event_description`
          - `venue_description`

          und gib das Ergebnis im selben JSON-Format zurück wie in `Output`.

          Wichtig:
          Die ermittelten Links und Informationen müssen für das Zielmodell „offiziell oder belastbar genug“ sein.

          Dabei gelten folgende Regeln:

          1. Bevorzuge für Links in dieser Reihenfolge:
            - `official`: offizielle Website oder offiziell wirkender verifizierbarer Künstler-/Projekt-/Venue-Account
            - `promoter`: offizielle Projekt-, Veranstalter- oder Tour-Seite eines bekannten Promoters / Managements / Veranstalters
            - `event_listing`: belastbare Event-Seite eines bekannten Ticketing- oder Venue-Portals
            - `social_post`: einzelner konkreter Social-Media-Post, wenn kein offizieller Account oder keine bessere Quelle verfügbar ist

          2. Verwende einen Link nur dann, wenn er eindeutig dem Artist, Projekt, Event oder Venue zugeordnet werden kann.

          3. Wenn kein ausreichend belastbarer Link gefunden wird, setze das Feld auf `null`.

          4. Erfinde keine Links, Genres oder Beschreibungen.

          5. Wenn ein Event kein Musik-Act ist, sondern z. B. Theater, Schauspiel, Show oder Lesung, dann modelliere es fachlich korrekt und verwende passende Genres statt Musikgenres.

          6. Bei Projekt- oder Tour-Formaten wie z. B. Ensemble-, Tribute-, Jubiläums- oder Mehrkünstler-Events dürfen auch projektbezogene oder promoterbezogene Links verwendet werden, wenn keine klaren offiziellen Artist-Accounts existieren.

          7. Beschreibungen sollen nüchtern, präzise und faktennah sein:
            - `artist_description`: beschreibt Artist, Projekt oder Produktion
            - `event_description`: beschreibt das konkrete Event bzw. Tour-/Show-Format
            - `venue_description`: beschreibt den Veranstaltungsort

          8. Gib zu jedem Link zusätzlich den Typ der Quelle an:
            - `official`
            - `promoter`
            - `event_listing`
            - `social_post`

          Falls du für einen Link keinen ausreichend belastbaren Treffer findest, gib für Link und Link-Typ jeweils `null` zurück.

          Antwort nur als JSON.

          Input:
          #{JSON.pretty_generate(items.map(&:as_json))}
        TEXT
      end

      def output_format
        {
          type: "json_schema",
          name: OUTPUT_SCHEMA_NAME,
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            required: [ OUTPUT_ITEMS_KEY ],
            properties: {
              OUTPUT_ITEMS_KEY => {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: %w[event_id genre venue artist_description event_description venue_description youtube_link instagram_link homepage_link facebook_link],
                  properties: {
                    event_id: { type: "integer" },
                    genre: {
                      type: "array",
                      items: { type: "string" }
                    },
                    venue: { type: [ "string", "null" ] },
                    artist_description: { type: [ "string", "null" ] },
                    event_description: { type: [ "string", "null" ] },
                    venue_description: { type: [ "string", "null" ] },
                    youtube_link: { type: [ "string", "null" ] },
                    instagram_link: { type: [ "string", "null" ] },
                    homepage_link: { type: [ "string", "null" ] },
                    facebook_link: { type: [ "string", "null" ] }
                  }
                }
              }
            }
          }
        }
      end

      def extract_payload!(response)
        parsed_payload = extract_parsed_payload(response)
        return extract_items_from_payload(parsed_payload) if parsed_payload.present?

        output_text = extract_output_text(response)
        raise Error, "OpenAI-Antwort enthält keinen JSON-Text." if output_text.blank?

        payload = JSON.parse(output_text)
        extract_items_from_payload(payload)
      rescue JSON::ParserError => e
        logger.error("[LlmEnrichmentImporter] run_id=#{run.id} invalid json response=#{safe_response_dump(response)}")
        raise Error, "OpenAI-Antwort enthält ungültiges JSON: #{e.message}"
      end

      def extract_items_from_payload(payload)
        raise Error, "OpenAI-Antwort ist kein JSON-Objekt." unless payload.is_a?(Hash)

        items = payload[OUTPUT_ITEMS_KEY]
        raise Error, "OpenAI-Antwort enthält kein #{OUTPUT_ITEMS_KEY}-Array." unless items.is_a?(Array)

        items
      end

      def extract_parsed_payload(response)
        return extract_parsed_payload_from_object(response) if response.respond_to?(:output)

        extract_parsed_payload_from_hash(response)
      end

      def extract_parsed_payload_from_object(response)
        Array(response.output).each do |item|
          next unless item.respond_to?(:content)

          Array(item.content).each do |content|
            next unless content.respond_to?(:type) && content.type.to_sym == :output_text

            parsed = content.respond_to?(:parsed) ? content.parsed : nil
            next if parsed.blank?

            return parsed.respond_to?(:to_h) ? parsed.to_h : parsed
          end
        end

        nil
      end

      def extract_parsed_payload_from_hash(response)
        Array(response["output"]).each do |item|
          Array(item["content"]).each do |content|
            next unless content["type"].to_s == "output_text"

            parsed = content["parsed"] || content[:parsed]
            return parsed if parsed.present?
          end
        end

        nil
      end

      def extract_output_text(response)
        return response.output_text.to_s if response.respond_to?(:output_text)

        response["output_text"].to_s.presence || extract_output_text_from_hash_content(response)
      end

      def extract_output_text_from_hash_content(response)
        Array(response["output"]).flat_map { |item| Array(item["content"]) }
          .find { |content| content["type"] == "output_text" }
          &.fetch("text", "")
          .to_s
      end

      def safe_response_dump(response)
        return response.deep_to_h.inspect if response.respond_to?(:deep_to_h)
        return response.to_h.inspect if response.respond_to?(:to_h)

        response.inspect
      end

      def persist_batch!(payload:, run:, batch_event_ids:)
        allowed_event_ids = batch_event_ids.map(&:to_i)
        seen_event_ids = {}

        ActiveRecord::Base.transaction do
          payload.each do |item|
            attributes = normalize_payload_item(item)
            event_id = attributes.fetch(:event_id)

            unless allowed_event_ids.include?(event_id)
              raise Error, "OpenAI-Antwort enthält event_id=#{event_id}, die nicht im aktuellen Batch liegt."
            end

            if seen_event_ids[event_id]
              raise Error, "OpenAI-Antwort enthält event_id=#{event_id} mehrfach."
            end

            seen_event_ids[event_id] = true

            EventLlmEnrichment.find_or_create_by!(event_id: event_id) do |enrichment|
              enrichment.source_run = run
              enrichment.genre = attributes[:genre]
              enrichment.venue = attributes[:venue]
              enrichment.artist_description = attributes[:artist_description]
              enrichment.event_description = attributes[:event_description]
              enrichment.venue_description = attributes[:venue_description]
              enrichment.youtube_link = attributes[:youtube_link]
              enrichment.instagram_link = attributes[:instagram_link]
              enrichment.homepage_link = attributes[:homepage_link]
              enrichment.facebook_link = attributes[:facebook_link]
              enrichment.model = client_model
              enrichment.prompt_version = PROMPT_VERSION
              enrichment.raw_response = item.is_a?(Hash) ? item.deep_stringify_keys : {}
            end
          end
        end

        seen_event_ids.size
      end

      def normalize_payload_item(item)
        unless item.is_a?(Hash)
          raise Error, "OpenAI-Antwort enthält einen ungültigen Eintrag."
        end

        {
          event_id: Integer(item["event_id"] || item[:event_id], exception: false),
          genre: Array(item["genre"] || item[:genre]),
          venue: item["venue"] || item[:venue],
          artist_description: item["artist_description"] || item[:artist_description],
          event_description: item["event_description"] || item[:event_description],
          venue_description: item["venue_description"] || item[:venue_description],
          youtube_link: item["youtube_link"] || item[:youtube_link],
          instagram_link: item["instagram_link"] || item[:instagram_link],
          homepage_link: item["homepage_link"] || item[:homepage_link],
          facebook_link: item["facebook_link"] || item[:facebook_link]
        }.tap do |attributes|
          raise Error, "OpenAI-Antwort enthält keine gültige event_id." if attributes[:event_id].blank?
        end
      end

      def touch_run_heartbeat!(extra_metadata = {})
        metadata = current_run_metadata.merge(extra_metadata.deep_stringify_keys)
        run.update_columns(metadata: metadata, updated_at: Time.current)
        Backend::ImportRunsBroadcaster.broadcast!
      end

      def update_run_progress!(selected_count:, skipped_count:, enriched_count:, batches_count:, batches_processed:, **extra_metadata)
        run.update!(
          fetched_count: selected_count,
          filtered_count: skipped_count,
          imported_count: enriched_count,
          upserted_count: batches_processed,
          metadata: current_run_metadata.merge(
            {
              "events_selected_count" => selected_count,
              "events_skipped_count" => skipped_count,
              "events_enriched_count" => enriched_count,
              "batches_count" => batches_count,
              "batches_processed_count" => batches_processed
            }
          ).merge(extra_metadata.deep_stringify_keys)
        )
        Backend::ImportRunsBroadcaster.broadcast!
      end

      def stop_requested?
        ActiveModel::Type::Boolean.new.cast(current_run_metadata["stop_requested"])
      end

      def canceled_result(selected_events:, skipped_count:, enriched_count:, batches_count:, merge_run:)
        Result.new(
          selected_count: selected_events.count,
          skipped_count: skipped_count,
          enriched_count: enriched_count,
          batches_count: batches_count,
          merge_run_id: merge_run.id,
          model: client_model,
          canceled: true
        )
      end

      def normalized_metadata(metadata)
        metadata.is_a?(Hash) ? metadata.deep_stringify_keys : {}
      end

      def current_run_metadata
        normalized_metadata(run.reload.metadata)
      end

      def client_model
        client.model
      end
    end
  end
end
