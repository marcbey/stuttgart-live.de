require "json"

module Importing
  module LlmEnrichment
    class Importer
      RUN_STALE_AFTER = 4.hours
      RUN_HEARTBEAT_STALE_AFTER = 10.minutes
      BATCH_SIZE = 25
      PROMPT_VERSION = "v1"
      OUTPUT_SCHEMA_NAME = "event_llm_enrichment_batch".freeze
      OUTPUT_ITEMS_KEY = "events".freeze
      LINK_FIELDS = %i[youtube_link instagram_link homepage_link facebook_link].freeze

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

      Result = Data.define(
        :selected_count,
        :skipped_count,
        :enriched_count,
        :batches_count,
        :merge_run_id,
        :model,
        :links_checked_count,
        :links_rejected_count,
        :links_unverifiable_count,
        :canceled
      )

      def initialize(run:, client: OpenAi::ResponsesClient.new, logger: Importing::Logging.logger, link_validator: nil)
        @run = run
        @client = client
        @logger = logger
        @link_validator = link_validator || LinkValidator.new
      end

      def call
        reset_link_validation_counts!
        selection_time = Time.current
        selected_events = selected_events_scope(selection_time)
        selected_count = selected_events.count
        skipped_count = skip_existing_enrichments? ? already_enriched_count(selected_events) : 0
        pending_events = pending_events_scope(selected_events).order(:start_at, :id).to_a
        batches = pending_events.each_slice(BATCH_SIZE).to_a
        enriched_count = 0
        batches_processed = 0

        logger.info("[LlmEnrichmentImporter] run_id=#{run.id} started selected=#{selected_count} skipped=#{skipped_count} batches=#{batches.count}")

        update_run_progress!(
          selected_count: selected_count,
          skipped_count: skipped_count,
          enriched_count: enriched_count,
          batches_count: batches.count,
          batches_processed: batches_processed,
          "merge_run_id" => nil,
          "batch_size" => BATCH_SIZE,
          "model" => client_model,
          "links_checked_count" => links_checked_count,
          "links_rejected_count" => links_rejected_count,
          "links_unverifiable_count" => links_unverifiable_count
        )

        batches.each_with_index do |batch_events, index|
          check_stop_requested!(message: "before batch", current_batch: index + 1)

          touch_run_heartbeat!("current_batch" => index + 1)
          logger.info("[LlmEnrichmentImporter] run_id=#{run.id} requesting batch=#{index + 1}/#{batches.count} size=#{batch_events.size}")

          items = batch_events.map { |event| item_for(event) }
          response = client.create!(input: request_input(items), text_format: output_format)
          check_stop_requested!(message: "after response", current_batch: index + 1)
          payload = extract_payload!(response)
          check_stop_requested!(message: "before persist", current_batch: index + 1)
          enriched_count += persist_batch!(
            payload:,
            run:,
            batch_event_ids: batch_events.map(&:id),
            stop_requested: -> { stop_requested? }
          )
          batches_processed += 1
          logger.info("[LlmEnrichmentImporter] run_id=#{run.id} completed batch=#{batches_processed}/#{batches.count} enriched_total=#{enriched_count}")

          update_run_progress!(
            selected_count: selected_count,
            skipped_count: skipped_count,
            enriched_count: enriched_count,
            batches_count: batches.count,
            batches_processed: batches_processed,
            "current_batch" => batches_processed,
            "links_checked_count" => links_checked_count,
            "links_rejected_count" => links_rejected_count,
            "links_unverifiable_count" => links_unverifiable_count
          )
        end

        Result.new(
          selected_count: selected_count,
          skipped_count: skipped_count,
          enriched_count: enriched_count,
          batches_count: batches.count,
          merge_run_id: nil,
          model: client_model,
          links_checked_count: links_checked_count,
          links_rejected_count: links_rejected_count,
          links_unverifiable_count: links_unverifiable_count,
          canceled: false
        )
      rescue Importing::StopRequested
        logger.info("[LlmEnrichmentImporter] run_id=#{run.id} stopped cooperatively")
        canceled_result(selected_count:, skipped_count:, enriched_count:, batches_count: batches.count)
      rescue StandardError => e
        logger.error("[LlmEnrichmentImporter] run_id=#{run.id} failed: #{e.class}: #{e.message}")
        raise
      end

      private

      Error = Class.new(StandardError)

      attr_reader :client, :link_validator, :logger, :run

      def selected_events_scope(selection_time)
        return Event.where(id: target_event_id) if single_event_run?

        Event.where("start_at >= ?", selection_time)
      end

      def already_enriched_count(scope)
        scope.joins(:llm_enrichment).distinct.count
      end

      def pending_events_scope(scope)
        return scope unless skip_existing_enrichments?

        scope.where.missing(:llm_enrichment)
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
        AppSetting.llm_enrichment_prompt_template.gsub("{{input_json}}", JSON.pretty_generate(items.map(&:as_json)))
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

      def persist_batch!(payload:, run:, batch_event_ids:, stop_requested: nil)
        allowed_event_ids = batch_event_ids.map(&:to_i)
        seen_event_ids = {}
        Importing::CooperativeStop.check!(stop_requested)

        ActiveRecord::Base.transaction do
          payload.each do |item|
            Importing::CooperativeStop.check!(stop_requested)
            attributes = normalize_payload_item(item)
            event_id = attributes.fetch(:event_id)

            unless allowed_event_ids.include?(event_id)
              raise Error, "OpenAI-Antwort enthält event_id=#{event_id}, die nicht im aktuellen Batch liegt."
            end

            if seen_event_ids[event_id]
              logger.warn(
                "[LlmEnrichmentImporter] run_id=#{run.id} skipping duplicate response item for event_id=#{event_id}"
              )
              next
            end

            seen_event_ids[event_id] = true
            validated_attributes, validation_payload = validate_link_attributes(attributes)
            raw_response = item.is_a?(Hash) ? item.deep_stringify_keys : {}
            raw_response["link_validation"] = validation_payload if validation_payload.present?

            enrichment = EventLlmEnrichment.find_or_initialize_by(event_id: event_id)
            enrichment.source_run = run
            enrichment.genre = validated_attributes[:genre]
            enrichment.venue = validated_attributes[:venue]
            enrichment.artist_description = validated_attributes[:artist_description]
            enrichment.event_description = validated_attributes[:event_description]
            enrichment.venue_description = validated_attributes[:venue_description]
            enrichment.youtube_link = validated_attributes[:youtube_link]
            enrichment.instagram_link = validated_attributes[:instagram_link]
            enrichment.homepage_link = validated_attributes[:homepage_link]
            enrichment.facebook_link = validated_attributes[:facebook_link]
            enrichment.model = client_model
            enrichment.prompt_version = PROMPT_VERSION
            enrichment.raw_response = raw_response
            enrichment.save!
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

      def validate_link_attributes(attributes)
        validated_attributes = attributes.deep_dup
        validation_payload = {}

        LINK_FIELDS.each do |field_name|
          url = attributes[field_name].to_s.strip
          next if url.blank?

          result = link_validator.call(url:, field_name:)
          validation_payload[field_name.to_s] = result.as_json
          increment_link_validation_counts!(result)
          validated_attributes[field_name] = result.sanitized_url
        rescue StandardError => e
          increment_link_validation_counts!(
            LinkValidator::Result.new(
              accepted: true,
              sanitized_url: url,
              status: "kept_unverifiable",
              final_url: nil,
              http_status: nil,
              error_class: e.class.to_s,
              matched_phrase: nil,
              checked_at: Time.current
            )
          )
          validation_payload[field_name.to_s] = {
            status: "kept_unverifiable",
            error_class: e.class.to_s,
            checked_at: Time.current.iso8601
          }
          validated_attributes[field_name] = url
        end

        [ validated_attributes, validation_payload ]
      end

      def touch_run_heartbeat!(extra_metadata = {})
        return unless run_running?

        metadata = current_run_metadata.merge(extra_metadata.deep_stringify_keys)
        run.update_columns(metadata: metadata, updated_at: Time.current)
        Backend::ImportRunsBroadcaster.broadcast!
      end

      def update_run_progress!(selected_count:, skipped_count:, enriched_count:, batches_count:, batches_processed:, **extra_metadata)
        return unless run_running?

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

      def check_stop_requested!(message:, **details)
        Importing::CooperativeStop.check!(-> { stop_requested? }, message:, **details)
      end

      def run_running?
        run.reload.status == "running"
      end

      def canceled_result(selected_count:, skipped_count:, enriched_count:, batches_count:)
        Result.new(
          selected_count: selected_count,
          skipped_count: skipped_count,
          enriched_count: enriched_count,
          batches_count: batches_count,
          merge_run_id: nil,
          model: client_model,
          links_checked_count: links_checked_count,
          links_rejected_count: links_rejected_count,
          links_unverifiable_count: links_unverifiable_count,
          canceled: true
        )
      end

      def increment_link_validation_counts!(result)
        @links_checked_count += 1
        @links_rejected_count += 1 if result.rejected?
        @links_unverifiable_count += 1 if result.unverifiable?
      end

      def reset_link_validation_counts!
        @links_checked_count = 0
        @links_rejected_count = 0
        @links_unverifiable_count = 0
      end

      def links_checked_count
        @links_checked_count || 0
      end

      def links_rejected_count
        @links_rejected_count || 0
      end

      def links_unverifiable_count
        @links_unverifiable_count || 0
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

      def refresh_existing?
        ActiveModel::Type::Boolean.new.cast(current_run_metadata["refresh_existing"])
      end

      def single_event_run?
        target_event_id.present?
      end

      def skip_existing_enrichments?
        !refresh_existing? && !single_event_run?
      end

      def target_event_id
        Integer(current_run_metadata["target_event_id"], exception: false)
      end
    end
  end
end
