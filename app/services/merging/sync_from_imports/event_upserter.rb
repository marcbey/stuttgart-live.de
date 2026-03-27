require "set"

module Merging
  class SyncFromImports
    class EventUpserter
      def initialize(merge_run_id:, logger:, priority_map:, match_strategy:)
        @merge_run_id = merge_run_id
        @logger = logger
        @priority_map = priority_map
        @match_strategy = match_strategy
      end

      def call(records)
        primary = records.first
        fingerprint = fingerprint_for(primary)

        match_result = find_existing_event(records, fingerprint)
        event = resolve_event_for_fingerprint(match_result&.event || Event.new, fingerprint)
        created_now = event.new_record?
        duplicate_now = similarity_duplicate?(match_result)
        previous_event_series = event.event_series

        assign_event_attributes(event, records, fingerprint:, created_now:)

        merged_images = merged_image_candidates(records)
        offers = build_offer_attributes(records)
        images_present = merged_images.any?
        completeness = Editorial::EventCompletenessChecker.new(event: event, offers: offers, images_present: images_present).call
        event.completeness_score = completeness.score
        event.completeness_flags = completeness.flags

        apply_status_rules(event, created_now:, images_present:, ready_for_publish: completeness.ready_for_publish?)
        updated_now = event.changed? && !created_now

        event.save! if created_now || event.changed?
        cleanup_orphaned_event_series!(previous_event_series, current_series: event.event_series)

        offers_upserted = sync_offers!(event, offers)
        images_changed = sync_event_images!(event, merged_images)

        effective_updated = (updated_now || images_changed) && !created_now

        if created_now || effective_updated
          Editorial::EventChangeLogger.log!(
            event: event,
            action: created_now ? "merged_create" : "merged_update",
            user: nil,
            metadata: merge_change_metadata(records)
          )
        end

        logger.info("[Merging::SyncFromImports] synced event ##{event.id} with #{records.size} source records")

        [ event, created_now, effective_updated, duplicate_now, offers_upserted ]
      end

      private

      attr_reader :logger, :match_strategy, :merge_run_id, :priority_map

      def assign_event_attributes(event, records, fingerprint:, created_now:)
        event.source_fingerprint = fingerprint
        event.source_snapshot = build_source_snapshot(event, records)
        event.primary_source = prioritized_primary_source(event.source_snapshot, fallback: records.first.source)
        assign_event_series(event, records)

        if created_now
          event.title = first_present(records, &:title)
          event.artist_name = first_present(records, &:artist_name)
          event.city = first_present_or_nil(records, &:city)
          event.promoter_id = first_present_or_nil(records, &:promoter_id)
          event.youtube_url = first_present_or_nil(records, &:youtube_url)
          event.homepage_url = first_present_or_nil(records, &:homepage_url)
          event.facebook_url = first_present_or_nil(records, &:facebook_url)
          imported_description_text = first_present_or_nil(records, &:event_info)
          event.event_info = imported_description_text if imported_description_text.present?
        end

        event.start_at = first_present_time(records, &:start_at)
        event.doors_at = first_present_time(records, &:doors_at)
        event.venue = first_present(records, &:venue)
        event.badge_text = first_present_or_nil(records, &:badge_text)
        event.min_price = first_present_decimal(records, &:min_price)
        event.max_price = first_present_decimal(records, &:max_price)
      end

      def assign_event_series(event, records)
        return if event.event_series_locked_by_editor?

        series = imported_event_series_for(records)
        event.event_series_assignment = "auto"

        if series.present?
          event.event_series = series
        elsif event.event_series&.imported?
          event.event_series = nil
        end
      end

      def apply_status_rules(event, created_now:, images_present:, ready_for_publish:)
        return if event.status == "rejected"

        if created_now
          if auto_publishable?(event, images_present:)
            event.status = "published"
            event.auto_published = true
            event.sync_publication_fields
          else
            event.status = "needs_review"
            event.auto_published = false
            event.published_at = nil if event.published_by_id.nil?
          end
          return
        end

        if event.published? && event.auto_published?
          return if auto_publishable?(event, images_present:)

          event.status = "needs_review"
          event.auto_published = false
          event.published_at = nil if event.published_by_id.nil?
          return
        end

        return unless event.status == "needs_review" && ready_for_publish

        event.status = "published"
        event.auto_published = true
        event.sync_publication_fields
      end

      def auto_publishable?(event, images_present:)
        event.artist_name.present? &&
          event.title.present? &&
          event.start_at.present? &&
          event.city.present? &&
          event.venue.present? &&
          images_present
      end

      def find_existing_event(records, _fingerprint)
        match_strategy.call(records:)
      end

      def resolve_event_for_fingerprint(event, fingerprint)
        exact_event = Event.find_by(source_fingerprint: fingerprint)
        return event if exact_event.blank?
        return event if event.persisted? && event.id == exact_event.id

        exact_event
      end

      def similarity_duplicate?(match_result)
        return false if match_result.nil?

        !%w[source_snapshot exact_fingerprint].include?(match_result.reason.to_s)
      end

      def sync_offers!(event, offers)
        existing = event.event_offers.index_by { |offer| [ offer.source, offer.source_event_id ] }
        upserted = 0
        touched_sources = offers.map { |attrs| attrs[:source].to_s }.uniq

        offers.each do |attrs|
          key = [ attrs[:source], attrs[:source_event_id] ]
          offer = existing.delete(key) || event.event_offers.new
          offer.assign_attributes(attrs)
          next unless offer.new_record? || offer.changed?

          offer.save!
          upserted += 1
        end

        existing.each_value do |offer|
          next unless touched_sources.include?(offer.source.to_s)

          offer.destroy!
        end
        upserted
      end

      def build_offer_attributes(records)
        records.map do |record|
          {
            source: record.source,
            source_event_id: record.external_event_id,
            ticket_url: record.ticket_url,
            ticket_price_text: record.ticket_price_text,
            sold_out: false,
            priority_rank: priority_for(record.source),
            metadata: build_offer_metadata(record)
          }
        end
      end

      def merged_image_candidates(records)
        candidates = []
        seen = Set.new

        records
          .flat_map(&:images)
          .sort_by { |image| [ priority_for(image.source), image.position.to_i, image.image_type.to_s ] }
          .each do |image|
            key = image_key(source: image.source, image_type: image.image_type, image_url: image.image_url)
            next if seen.include?(key)

            seen << key
            candidates << {
              source: image.source,
              image_type: image.image_type,
              image_url: image.image_url,
              role: image.role,
              aspect_hint: image.aspect_hint,
              position: candidates.length
            }
          end

        candidates
      end

      def sync_event_images!(event, candidates)
        touched_sources = candidates.map { |candidate| candidate[:source].to_s }.uniq
        Importing::ImportEventImagesSync.call(owner: event, candidates: candidates, source: touched_sources)
      end

      def fingerprint_for(record)
        DuplicationKey.for_record(record)
      end

      def build_source_snapshot(event, records)
        existing_sources = event.source_snapshot.is_a?(Hash) ? Array(event.source_snapshot["sources"]) : []
        merged_sources = existing_sources.index_by { |source| source_snapshot_key(source) }

        records.each do |record|
          source = build_source_snapshot_source(record)
          merged_sources[source_snapshot_key(source)] = source
        end

        {
          "sources" => merged_sources.values.sort_by do |source|
            [
              priority_for(source["source"]),
              source["source"].to_s,
              source["source_identifier"].to_s,
              source["external_event_id"].to_s
            ]
          end
        }
      end

      def build_source_snapshot_source(record)
        snapshot = {
          "source" => record.source,
          "source_identifier" => record.source_identifier,
          "external_event_id" => record.external_event_id,
          "artist_name" => record.artist_name,
          "title" => record.title,
          "start_at" => record.start_at&.iso8601,
          "doors_at" => record.doors_at&.iso8601,
          "city" => record.city,
          "venue" => record.venue,
          "promoter_id" => record.promoter_id,
          "badge_text" => record.badge_text,
          "youtube_url" => record.youtube_url,
          "homepage_url" => record.homepage_url,
          "facebook_url" => record.facebook_url,
          "event_info" => record.event_info,
          "min_price" => decimal_as_json(record.min_price),
          "max_price" => decimal_as_json(record.max_price),
          "genre" => record.genre,
          "images" =>
            record.images.map do |image|
              {
                "source" => image.source,
                "image_type" => image.image_type,
                "image_url" => image.image_url,
                "role" => image.role,
                "aspect_hint" => image.aspect_hint,
                "position" => image.position
              }
            end,
          "raw_payload" => record.raw_payload
        }

        if record.series_reference.present?
          snapshot["event_series"] = {
            "source_type" => record.series_reference.source_type,
            "source_key" => record.series_reference.source_key,
            "name" => record.series_reference.name
          }.compact
        end

        snapshot
      end

      def prioritized_primary_source(source_snapshot, fallback:)
        sources = source_snapshot.is_a?(Hash) ? Array(source_snapshot["sources"]) : []
        best_source = sources.min_by { |source| [ priority_for(source["source"]), source["source"].to_s ] }
        best_source&.fetch("source", nil).presence || fallback
      end

      def imported_event_series_for(records)
        reference = records.filter_map(&:series_reference).first
        EventSeriesResolver.ensure_imported!(reference)
      end

      def source_snapshot_key(source)
        [
          source["source"].to_s,
          source["external_event_id"].to_s
        ]
      end

      def first_present(records)
        records.each do |record|
          value = yield(record).to_s.strip
          return value if value.present?
        end

        ""
      end

      def first_present_or_nil(records)
        records.each do |record|
          value = yield(record).to_s.strip
          return value if value.present?
        end

        nil
      end

      def first_present_decimal(records)
        records.each do |record|
          value = yield(record)
          decimal = normalize_decimal(value)
          return decimal if decimal.present?
        end

        nil
      end

      def first_present_time(records)
        records.each do |record|
          value = yield(record)
          return value if value.present?
        end

        nil
      end

      def priority_for(source)
        priority_map.fetch(source, 999)
      end

      def build_offer_metadata(record)
        metadata = {}

        min_price = decimal_as_json(record.min_price)
        max_price = decimal_as_json(record.max_price)
        metadata["min_price"] = min_price if min_price.present?
        metadata["max_price"] = max_price if max_price.present?

        metadata
      end

      def decimal_as_json(value)
        decimal = normalize_decimal(value)
        return nil if decimal.nil?

        decimal.to_s("F")
      end

      def normalize_decimal(value)
        return value if value.is_a?(BigDecimal)

        return nil if value.blank?

        BigDecimal(value.to_s)
      rescue ArgumentError
        nil
      end

      def image_key(source:, image_type:, image_url:)
        [
          source.to_s.strip.downcase,
          image_type.to_s.strip,
          image_url.to_s.strip.downcase
        ]
      end

      def merge_change_metadata(records)
        {
          source_types: records.map(&:source).uniq,
          external_event_ids: records.map(&:external_event_id),
          merge_run_id: merge_run_id
        }.compact
      end

      def cleanup_orphaned_event_series!(previous_series, current_series:)
        return if previous_series.blank?
        return if current_series.present? && previous_series.id == current_series.id

        previous_series.destroy_if_orphaned!
      end
    end
  end
end
