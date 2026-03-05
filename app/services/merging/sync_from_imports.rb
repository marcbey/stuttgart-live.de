require "set"

module Merging
  class SyncFromImports
    Result = Data.define(
      :import_records_count,
      :groups_count,
      :events_created_count,
      :events_updated_count,
      :offers_upserted_count
    )

    ImportRecord = Data.define(
      :source,
      :external_event_id,
      :concert_date,
      :begin_time,
      :city,
      :venue_name,
      :title,
      :artist_name,
      :organizer_name,
      :promoter_id,
      :ticket_url,
      :images,
      :raw_payload
    )

    ImportImage = Data.define(
      :source,
      :image_type,
      :image_url,
      :role,
      :aspect_hint,
      :position
    )

    def initialize(merge_run_id: nil, logger: Rails.logger)
      @merge_run_id = merge_run_id
      @logger = logger
      @priority_map = ProviderPriorityMap.call
    end

    def call
      records = import_records
      groups = records.group_by { |record| fingerprint_for(record) }

      created = 0
      updated = 0
      offers_upserted = 0

      ActiveRecord::Base.transaction do
        groups.each_value do |records|
          ordered_records = ordered_records_for_group(records)
          event, created_now, updated_now, offers_count = upsert_event_for(ordered_records)
          created += 1 if created_now
          updated += 1 if updated_now
          offers_upserted += offers_count

          logger.info("[Merging::SyncFromImports] synced event ##{event.id} with #{ordered_records.size} source records")
        end
      end

      Result.new(
        import_records_count: records.size,
        groups_count: groups.count,
        events_created_count: created,
        events_updated_count: updated,
        offers_upserted_count: offers_upserted
      )
    end

    private

    attr_reader :merge_run_id, :logger, :priority_map

    def import_records
      easyticket_records + eventim_records
    end

    def easyticket_records
      EasyticketImportEvent
        .active
        .includes(:import_event_images)
        .joins(:import_source)
        .where(import_sources: { active: true, source_type: "easyticket" })
        .map do |record|
          ensure_import_record_images!(record, source: "easyticket")

          ImportRecord.new(
            source: "easyticket",
            external_event_id: record.external_event_id,
            concert_date: record.concert_date,
            begin_time: begin_time_for_easyticket(record),
            city: record.city,
            venue_name: record.venue_name,
            title: record.title,
            artist_name: record.artist_name,
            organizer_name: organizer_name_for_easyticket(record),
            promoter_id: nil,
            ticket_url: record.ticket_url,
            images: images_for_import_record(record, fallback_source: "easyticket"),
            raw_payload: {
              dump_payload: record.dump_payload,
              detail_payload: record.detail_payload
            }
          )
        end
    end

    def eventim_records
      EventimImportEvent
        .active
        .includes(:import_event_images)
        .joins(:import_source)
        .where(import_sources: { active: true, source_type: "eventim" })
        .map do |record|
          ensure_import_record_images!(record, source: "eventim")

          ImportRecord.new(
            source: "eventim",
            external_event_id: record.external_event_id,
            concert_date: record.concert_date,
            begin_time: begin_time_for_eventim(record),
            city: record.city,
            venue_name: record.venue_name,
            title: record.title,
            artist_name: record.artist_name,
            organizer_name: organizer_name_for_eventim(record),
            promoter_id: promoter_id_for_eventim(record),
            ticket_url: record.ticket_url,
            images: images_for_import_record(record, fallback_source: "eventim"),
            raw_payload: {
              dump_payload: record.dump_payload,
              detail_payload: record.detail_payload
            }
          )
        end
    end

    def upsert_event_for(records)
      primary = records.first
      fingerprint = fingerprint_for(primary)

      event = Event.find_or_initialize_by(source_fingerprint: fingerprint)
      created_now = event.new_record?

      event.title = first_present(records, &:title)
      event.artist_name = first_present(records, &:artist_name)
      event.city = first_present(records, &:city)
      event.venue = first_present(records, &:venue_name)
      event.organizer_name = first_present(records, &:organizer_name).presence
      event.promoter_id = first_present(records, &:promoter_id).presence
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

      [ event, created_now, effective_updated, offers_upserted ]
    end

    def apply_status_rules(event, completeness, images_present:)
      return if event.status == "rejected"
      return if event.published? && !event.auto_published?

      if completeness.ready_for_publish? && images_present
        event.status = "published"
        event.auto_published = true
        event.published_at ||= Time.current
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
          sold_out: false,
          priority_rank: priority_for(record.source),
          metadata: {}
        }
      end
    end

    def ensure_import_record_images!(record, source:)
      association = record.import_event_images
      return if association.loaded? ? association.any? : association.exists?

      candidates =
        case source
        when "easyticket"
          Importing::Easyticket::PayloadProjection.new(
            dump_payload: record.dump_payload,
            detail_payload: record.detail_payload
          ).image_candidates
        when "eventim"
          Importing::Eventim::PayloadProjection.new(
            feed_payload: record.dump_payload
          ).image_candidates
        else
          []
        end

      sync_import_owner_images!(owner: record, source: source, candidates: candidates)
      association.reset
    end

    def images_for_import_record(record, fallback_source:)
      record.import_event_images.ordered.map do |image|
        source = image.source.to_s.strip.presence || fallback_source
        image_type = image.image_type.to_s.strip.presence || "image"
        image_url = ImportEventImage.normalize_image_url(image.image_url)
        next if image_url.blank?

        ImportImage.new(
          source: source,
          image_type: image_type,
          image_url: image_url,
          role: image.role.to_s.strip.presence || ImportEventImage.derive_role(source: source, image_type: image_type),
          aspect_hint: image.aspect_hint.to_s.strip.presence || ImportEventImage.derive_aspect_hint(url: image_url, image_type: image_type),
          position: image.position.to_i
        )
      end.compact
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
      existing_by_key = event.import_event_images.index_by do |image|
        image_key(source: image.source, image_type: image.image_type, image_url: image.image_url)
      end
      changed = false

      Array(candidates).each_with_index do |candidate, index|
        key = image_key(
          source: candidate[:source],
          image_type: candidate[:image_type],
          image_url: candidate[:image_url]
        )
        image = existing_by_key.delete(key) || event.import_event_images.new
        image.assign_attributes(
          source: candidate[:source],
          image_type: candidate[:image_type],
          image_url: candidate[:image_url],
          role: candidate[:role],
          aspect_hint: candidate[:aspect_hint],
          position: index
        )
        next unless image.new_record? || image.changed?

        image.save!
        changed = true
      end

      unless existing_by_key.empty?
        existing_by_key.each_value(&:destroy!)
        changed = true
      end

      changed
    end

    def sync_import_owner_images!(owner:, source:, candidates:)
      normalized_candidates = normalize_image_candidates(candidates, source: source)
      existing_by_key = owner.import_event_images.index_by do |image|
        image_key(source: image.source, image_type: image.image_type, image_url: image.image_url)
      end

      normalized_candidates.each_with_index do |candidate, index|
        key = image_key(
          source: candidate[:source],
          image_type: candidate[:image_type],
          image_url: candidate[:image_url]
        )
        image = existing_by_key.delete(key) || owner.import_event_images.new
        image.assign_attributes(
          source: candidate[:source],
          image_type: candidate[:image_type],
          image_url: candidate[:image_url],
          role: candidate[:role],
          aspect_hint: candidate[:aspect_hint],
          position: index
        )
        image.save! if image.new_record? || image.changed?
      end

      existing_by_key.each_value(&:destroy!)
    end

    def normalize_image_candidates(candidates, source:)
      seen = Set.new

      Array(candidates).filter_map do |candidate|
        row = candidate.respond_to?(:to_h) ? candidate.to_h : {}
        image_url = ImportEventImage.normalize_image_url(row[:image_url] || row["image_url"])
        next if image_url.blank?

        image_type = (row[:image_type] || row["image_type"]).to_s.strip.presence || "image"
        normalized_source = source.to_s
        key = image_key(source: normalized_source, image_type: image_type, image_url: image_url)
        next if seen.include?(key)

        seen << key
        {
          source: normalized_source,
          image_type: image_type,
          image_url: image_url,
          role: (row[:role] || row["role"]).to_s.strip.presence || ImportEventImage.derive_role(source: normalized_source, image_type: image_type),
          aspect_hint: (row[:aspect_hint] || row["aspect_hint"]).to_s.strip.presence || ImportEventImage.derive_aspect_hint(url: image_url, image_type: image_type)
        }
      end
    end

    def organizer_name_for_easyticket(record)
      return record.organizer_name.to_s.strip if record.organizer_name.to_s.strip.present?

      projection =
        Importing::Easyticket::PayloadProjection.new(
          dump_payload: record.dump_payload,
          detail_payload: record.detail_payload
        )
      projection.to_attributes&.dig(:organizer_name).to_s.strip
    end

    def promoter_id_for_eventim(record)
      return record.promoter_id.to_s.strip if record.promoter_id.to_s.strip.present?

      projection = Importing::Eventim::PayloadProjection.new(feed_payload: record.dump_payload)
      projection.to_attributes&.dig(:promoter_id).to_s.strip
    end

    def organizer_name_for_eventim(record)
      return record.organizer_name.to_s.strip if record.organizer_name.to_s.strip.present?

      projection = Importing::Eventim::PayloadProjection.new(feed_payload: record.dump_payload)
      projection.to_attributes&.dig(:organizer_name).to_s.strip
    end

    def begin_time_for_easyticket(record)
      raw_payload = record.dump_payload.is_a?(Hash) ? record.dump_payload : {}
      raw_payload["time"].to_s.strip
    end

    def begin_time_for_eventim(record)
      raw_payload = record.dump_payload.is_a?(Hash) ? record.dump_payload : {}
      raw_payload["eventtime"].to_s.strip
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

      fallback_hour = 20
      fallback_min = 0
      [ fallback_hour, fallback_min ]
    end

    def ordered_records_for_group(records)
      records.sort_by do |record|
        [
          priority_for(record.source),
          record.source.to_s,
          record.external_event_id.to_s
        ]
      end
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
              "organizer_name" => record.organizer_name,
              "promoter_id" => record.promoter_id,
              "ticket_url" => record.ticket_url,
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

    def priority_for(source)
      priority_map.fetch(source, 999)
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
