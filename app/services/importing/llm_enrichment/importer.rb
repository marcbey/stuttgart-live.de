require "json"

module Importing
  module LlmEnrichment
    class Importer
      RUN_STALE_AFTER = 4.hours
      RUN_HEARTBEAT_STALE_AFTER = 10.minutes
      BATCH_SIZE = 25
      EVENT_INFO_MAX_LENGTH = 1000
      PROMPT_VERSION = "v6"
      OUTPUT_SCHEMA_NAME = "event_llm_enrichment_batch".freeze
      OUTPUT_ITEMS_KEY = "events".freeze
      LOOKED_UP_LINK_FIELDS = %i[youtube_link instagram_link homepage_link facebook_link].freeze
      VALIDATED_LINK_FIELDS = %i[venue_external_url].freeze
      META_GENRE_TERMS = [
        "show",
        "shows",
        "concert",
        "concerts",
        "event",
        "events",
        "live event",
        "live-event",
        "veranstaltung",
        "veranstaltungen",
        "konzert",
        "konzerte",
        "live"
      ].freeze
      NORMALIZED_META_GENRE_TERMS = META_GENRE_TERMS.map do |term|
        term.to_s.strip.downcase.gsub(/[-\s]+/, " ")
      end.freeze

      Item = Data.define(:event_id, :artist_name, :event_name, :venue, :event_info) do
        def as_json(*)
          {
            event_id: event_id,
            artist_name: artist_name,
            event_name: event_name,
            venue: venue,
            event_info: event_info
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
        :web_search_provider,
        :links_checked_count,
        :links_rejected_count,
        :links_unverifiable_count,
        :web_search_request_count,
        :web_search_candidate_count,
        :links_found_via_web_search_count,
        :links_null_after_link_lookup_count,
        :canceled
      )

      def initialize(
        run:,
        client: OpenAi::ResponsesClient.new(
          model: AppSetting.llm_enrichment_model,
          temperature: AppSetting.llm_enrichment_temperature
        ),
        logger: Importing::Logging.logger,
        link_validator: nil,
        link_finder: nil
      )
        @run = run
        @client = client
        @logger = logger
        @link_validator = link_validator || LinkValidator.new
        @link_finder = link_finder || LinkFinder.new(link_validator: @link_validator)
      end

      def call
        reset_link_validation_counts!
        reset_link_lookup_counts!
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
          "web_search_provider" => web_search_provider,
          "links_checked_count" => links_checked_count,
          "links_rejected_count" => links_rejected_count,
          "links_unverifiable_count" => links_unverifiable_count,
          "web_search_request_count" => web_search_request_count,
          "web_search_candidate_count" => web_search_candidate_count,
          "links_found_via_web_search_count" => links_found_via_web_search_count,
          "links_null_after_link_lookup_count" => links_null_after_link_lookup_count
        )

        batches.each_with_index do |batch_events, index|
          check_stop_requested!(message: "before batch", current_batch: index + 1)

          touch_run_heartbeat!("current_batch" => index + 1)
          logger.info("[LlmEnrichmentImporter] run_id=#{run.id} processing batch=#{index + 1}/#{batches.count} size=#{batch_events.size} refresh_links_only=#{refresh_links_only?}")

          enriched_count +=
            if refresh_links_only?
              refresh_links_batch!(
                run: run,
                batch_events: batch_events,
                stop_requested: -> { stop_requested? }
              )
            else
              items = batch_events.map { |event| item_for(event) }
              response = client.create!(input: request_input(items), text_format: output_format)
              check_stop_requested!(message: "after response", current_batch: index + 1)
              payload = extract_payload!(response)
              check_stop_requested!(message: "before persist", current_batch: index + 1)
              persist_batch!(
                payload: payload,
                run: run,
                batch_events: batch_events,
                stop_requested: -> { stop_requested? }
              )
            end
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
            "links_unverifiable_count" => links_unverifiable_count,
            "web_search_request_count" => web_search_request_count,
            "web_search_candidate_count" => web_search_candidate_count,
            "links_found_via_web_search_count" => links_found_via_web_search_count,
            "links_null_after_link_lookup_count" => links_null_after_link_lookup_count
          )
        end

        Result.new(
          selected_count: selected_count,
          skipped_count: skipped_count,
          enriched_count: enriched_count,
          batches_count: batches.count,
          merge_run_id: nil,
          model: client_model,
          web_search_provider: web_search_provider,
          links_checked_count: links_checked_count,
          links_rejected_count: links_rejected_count,
          links_unverifiable_count: links_unverifiable_count,
          web_search_request_count: web_search_request_count,
          web_search_candidate_count: web_search_candidate_count,
          links_found_via_web_search_count: links_found_via_web_search_count,
          links_null_after_link_lookup_count: links_null_after_link_lookup_count,
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

      attr_reader :client, :link_finder, :link_validator, :logger, :run

      def selected_events_scope(selection_time)
        scope = target_event_ids.present? ? Event.where(id: target_event_ids) : Event.where("start_at >= ?", selection_time)
        scope = scope.joins(:llm_enrichment).distinct if refresh_links_only?

        scope
      end

      def already_enriched_count(scope)
        scope.joins(:llm_enrichment).distinct.count
      end

      def pending_events_scope(scope)
        return scope.joins(:llm_enrichment).distinct if refresh_links_only?
        return scope unless skip_existing_enrichments?

        scope.where.missing(:llm_enrichment)
      end

      def item_for(event)
        Item.new(
          event_id: event.id,
          artist_name: event.artist_name.to_s,
          event_name: event.title.to_s,
          venue: event.venue.to_s,
          event_info: truncated_event_info(event)
        )
      end

      def request_input(items)
        AppSetting.llm_enrichment_prompt_template.gsub("{{input_json}}", JSON.pretty_generate(items.map(&:as_json)))
      end

      def truncated_event_info(event)
        event.event_info.to_s[0, EVENT_INFO_MAX_LENGTH]
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
                  required: %w[event_id genre venue event_description venue_description venue_external_url venue_address],
                  properties: {
                    event_id: { type: "integer" },
                    genre: {
                      type: "array",
                      items: { type: "string" }
                    },
                    venue: { type: [ "string", "null" ] },
                    event_description: { type: [ "string", "null" ] },
                    venue_description: { type: [ "string", "null" ] },
                    venue_external_url: { type: [ "string", "null" ] },
                    venue_address: { type: [ "string", "null" ] }
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

      def persist_batch!(payload:, run:, batch_events:, stop_requested: nil)
        allowed_event_ids = batch_events.map(&:id)
        events_by_id = batch_events.index_by(&:id)
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
            filtered_attributes, genre_filter_payload = filter_meta_genres(attributes)
            validated_attributes, validation_payload = validate_payload_attributes(filtered_attributes)
            event = events_by_id.fetch(event_id)
            link_lookup_result = resolve_links_for(event)
            raw_response = item.is_a?(Hash) ? item.deep_stringify_keys : {}
            raw_response["genre_filter"] = genre_filter_payload if genre_filter_payload.present?
            raw_response["link_validation"] = validation_payload if validation_payload.present?
            raw_response["link_lookup"] = link_lookup_result.payload if link_lookup_result.payload.present?

            enrichment = EventLlmEnrichment.find_or_initialize_by(event_id: event_id)
            enrichment.source_run = run
            enrichment.genre = validated_attributes[:genre]
            enrichment.venue = validated_attributes[:venue]
            enrichment.event_description = validated_attributes[:event_description]
            enrichment.venue_description = validated_attributes[:venue_description]
            enrichment.venue_external_url = validated_attributes[:venue_external_url]
            enrichment.venue_address = validated_attributes[:venue_address]
            enrichment.youtube_link = link_lookup_result.links[:youtube_link]
            enrichment.instagram_link = link_lookup_result.links[:instagram_link]
            enrichment.homepage_link = link_lookup_result.links[:homepage_link]
            enrichment.facebook_link = link_lookup_result.links[:facebook_link]
            enrichment.model = client_model
            enrichment.prompt_version = PROMPT_VERSION
            enrichment.raw_response = raw_response
            enrichment.save!

            Venues::LlmFallbackAssignment.call(event: event, enrichment: enrichment)
          end
        end

        seen_event_ids.size
      end

      def refresh_links_batch!(run:, batch_events:, stop_requested: nil)
        refreshed_count = 0
        Importing::CooperativeStop.check!(stop_requested)

        ActiveRecord::Base.transaction do
          batch_events.each do |event|
            Importing::CooperativeStop.check!(stop_requested)
            enrichment = event.llm_enrichment
            next if enrichment.blank?

            link_lookup_result = resolve_links_for(event)
            raw_response = enrichment.raw_response.is_a?(Hash) ? enrichment.raw_response.deep_stringify_keys : {}
            raw_response["link_lookup"] = link_lookup_result.payload if link_lookup_result.payload.present?

            enrichment.source_run = run
            enrichment.youtube_link = link_lookup_result.links[:youtube_link]
            enrichment.instagram_link = link_lookup_result.links[:instagram_link]
            enrichment.homepage_link = link_lookup_result.links[:homepage_link]
            enrichment.facebook_link = link_lookup_result.links[:facebook_link]
            enrichment.model = enrichment.model.presence || client_model
            enrichment.prompt_version = enrichment.prompt_version.presence || PROMPT_VERSION
            enrichment.raw_response = raw_response
            enrichment.save!

            refreshed_count += 1
          end
        end

        refreshed_count
      end

      def normalize_payload_item(item)
        unless item.is_a?(Hash)
          raise Error, "OpenAI-Antwort enthält einen ungültigen Eintrag."
        end

        {
          event_id: Integer(item["event_id"] || item[:event_id], exception: false),
          genre: Array(item["genre"] || item[:genre]),
          venue: item["venue"] || item[:venue],
          event_description: item["event_description"] || item[:event_description],
          venue_description: item["venue_description"] || item[:venue_description],
          venue_external_url: item["venue_external_url"] || item[:venue_external_url],
          venue_address: item["venue_address"] || item[:venue_address]
        }.tap do |attributes|
          raise Error, "OpenAI-Antwort enthält keine gültige event_id." if attributes[:event_id].blank?
        end
      end

      def validate_payload_attributes(attributes)
        validated_attributes = attributes.deep_dup
        validation_payload = {}

        VALIDATED_LINK_FIELDS.each do |field_name|
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

      def resolve_links_for(event)
        result = link_finder.call(event:)
        increment_link_lookup_counts!(result)
        result.validation_results.each { |validation_result| increment_link_validation_counts!(validation_result) }
        result
      rescue StandardError => e
        LinkFinder::Result.new(
          links: LOOKED_UP_LINK_FIELDS.index_with { nil },
          payload: {
            "queries" => [],
            "fields" => LOOKED_UP_LINK_FIELDS.index_with do
              { "selected_url" => nil, "candidates" => [] }
            end,
            "error_class" => e.class.to_s,
            "error_message" => e.message
          },
          web_search_request_count: 0,
          web_search_candidate_count: 0,
          links_found_via_web_search_count: 0,
          links_null_after_link_lookup_count: LOOKED_UP_LINK_FIELDS.size,
          validation_results: []
        )
      end

      def filter_meta_genres(attributes)
        filtered_attributes = attributes.deep_dup
        filtered_genres = []
        rejected_terms = []

        Array(attributes[:genre]).each do |entry|
          genre = entry.to_s.strip
          next if genre.blank?

          if meta_genre?(genre)
            rejected_terms << genre
          else
            filtered_genres << genre
          end
        end

        filtered_attributes[:genre] = filtered_genres.uniq

        [
          filtered_attributes,
          rejected_terms.any? ? { "rejected_terms" => rejected_terms.uniq } : nil
        ]
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
          web_search_provider: web_search_provider,
          links_checked_count: links_checked_count,
          links_rejected_count: links_rejected_count,
          links_unverifiable_count: links_unverifiable_count,
          web_search_request_count: web_search_request_count,
          web_search_candidate_count: web_search_candidate_count,
          links_found_via_web_search_count: links_found_via_web_search_count,
          links_null_after_link_lookup_count: links_null_after_link_lookup_count,
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

      def increment_link_lookup_counts!(result)
        @web_search_request_count += result.web_search_request_count
        @web_search_candidate_count += result.web_search_candidate_count
        @links_found_via_web_search_count += result.links_found_via_web_search_count
        @links_null_after_link_lookup_count += result.links_null_after_link_lookup_count
      end

      def reset_link_lookup_counts!
        @web_search_request_count = 0
        @web_search_candidate_count = 0
        @links_found_via_web_search_count = 0
        @links_null_after_link_lookup_count = 0
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

      def web_search_provider
        AppSetting.llm_enrichment_web_search_provider
      end

      def web_search_request_count
        @web_search_request_count || 0
      end

      def web_search_candidate_count
        @web_search_candidate_count || 0
      end

      def links_found_via_web_search_count
        @links_found_via_web_search_count || 0
      end

      def links_null_after_link_lookup_count
        @links_null_after_link_lookup_count || 0
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

      def meta_genre?(genre)
        NORMALIZED_META_GENRE_TERMS.include?(normalize_meta_genre_term(genre))
      end

      def self.normalize_meta_genre_term(value)
        value.to_s.strip.downcase.gsub(/[-\s]+/, " ")
      end

      def normalize_meta_genre_term(value)
        self.class.normalize_meta_genre_term(value)
      end

      def refresh_existing?
        ActiveModel::Type::Boolean.new.cast(current_run_metadata["refresh_existing"])
      end

      def refresh_links_only?
        ActiveModel::Type::Boolean.new.cast(current_run_metadata["refresh_links_only"])
      end

      def single_event_run?
        target_event_ids.one? && target_event_id.present?
      end

      def skip_existing_enrichments?
        !refresh_existing? && target_event_ids.blank?
      end

      def target_event_ids
        @target_event_ids ||= begin
          ids = Array(current_run_metadata["target_event_ids"]).filter_map do |value|
            Integer(value, exception: false)
          end
          ids << target_event_id if target_event_id.present?
          ids.uniq
        end
      end

      def target_event_id
        Integer(current_run_metadata["target_event_id"], exception: false)
      end
    end
  end
end
