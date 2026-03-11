require "set"

module Merging
  class SyncFromImports
    class EventUpserter
      def initialize(merge_run_id:, logger:, priority_map:)
        @merge_run_id = merge_run_id
        @logger = logger
        @priority_map = priority_map
      end

      def call(records)
        primary = records.first
        fingerprint = fingerprint_for(primary)

        event = Event.find_or_initialize_by(source_fingerprint: fingerprint)
        created_now = event.new_record?

        event.title = first_present(records, &:title)
        event.artist_name = first_present(records, &:artist_name)
        event.city = first_present(records, &:city)
        event.venue = first_present(records, &:venue_name)
        event.promoter_id = first_present(records, &:promoter_id).presence
        event.min_price = first_present_decimal(records, &:min_price)
        event.max_price = first_present_decimal(records, &:max_price)
        imported_description_text = first_present_or_nil(records, &:description_text)
        event.event_info = imported_description_text if imported_description_text.present?
        event.start_at = start_at_for(primary.concert_date, primary.begin_time)
        event.primary_source = primary.source
        event.source_snapshot = build_source_snapshot(records)
        updated_now = event.changed?

        merged_images = merged_image_candidates(records)
        offers = build_offer_attributes(records)
        images_present = merged_images.any?
        completeness = Editorial::EventCompletenessChecker.new(event: event, offers: offers, images_present: images_present).call
        event.completeness_score = completeness.score
        event.completeness_flags = completeness.flags

        apply_status_rules(event, completeness, images_present: images_present)
        updated_now ||= event.changed?
        event.save! if created_now || updated_now

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

        [ event, created_now, effective_updated, offers_upserted ]
      end

      private

      attr_reader :logger, :merge_run_id, :priority_map

      def apply_status_rules(event, completeness, images_present:)
        return if event.status == "rejected"
        return if event.published? && !event.auto_published?

        if completeness.ready_for_publish? && images_present
          event.status = "published"
          event.auto_published = true
          event.sync_publication_fields
        else
          event.status = "needs_review"
          event.auto_published = false
          event.published_at = nil if event.published_by_id.nil?
        end
      end

      def sync_offers!(event, offers)
        existing = event.event_offers.index_by { |offer| [ offer.source, offer.source_event_id ] }
        upserted = 0

        offers.each do |attrs|
          key = [ attrs[:source], attrs[:source_event_id] ]
          offer = existing.delete(key) || event.event_offers.new
          offer.assign_attributes(attrs)
          next unless offer.new_record? || offer.changed?

          offer.save!
          upserted += 1
        end

        existing.each_value(&:destroy!)
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
        Importing::ImportEventImagesSync.call(owner: event, candidates: candidates)
      end

      def start_at_for(concert_date, begin_time)
        hour, min = parse_time_components(begin_time)
        Time.zone.local(concert_date.year, concert_date.month, concert_date.day, hour, min, 0)
      end

      def parse_time_components(value)
        raw = value.to_s.strip
        match = raw.match(/(?<!\d)(\d{1,2})[:.](\d{2})(?!\d)/)
        if match.present?
          hour = match[1].to_i
          min = match[2].to_i
          return [ hour, min ] if hour.between?(0, 23) && min.between?(0, 59)
        end

        [ 20, 0 ]
      end

      def fingerprint_for(record)
        [
          normalize_token(record.artist_name),
          normalize_token(record.venue_name),
          record.concert_date.iso8601
        ].join("::")
      end

      def normalize_token(value)
        I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]/, "")
      end

      def build_source_snapshot(records)
        {
          "sources" =>
            records.map do |record|
              {
                "source" => record.source,
                "external_event_id" => record.external_event_id,
                "concert_date" => record.concert_date.iso8601,
                "begin_time" => record.begin_time,
                "city" => record.city,
                "venue_name" => record.venue_name,
                "title" => record.title,
                "artist_name" => record.artist_name,
                "promoter_id" => record.promoter_id,
                "description_text" => record.description_text,
                "ticket_url" => record.ticket_url,
                "ticket_price_text" => record.ticket_price_text,
                "min_price" => decimal_as_json(record.min_price),
                "max_price" => decimal_as_json(record.max_price),
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
            end
        }
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
    end
  end
end
