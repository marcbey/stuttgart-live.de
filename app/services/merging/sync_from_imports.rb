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
      :city,
      :venue_name,
      :title,
      :artist_name,
      :ticket_url,
      :image_url,
      :raw_payload
    )

    def initialize(logger: Rails.logger)
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

    attr_reader :logger, :priority_map

    def import_records
      easyticket_records + eventim_records
    end

    def easyticket_records
      EasyticketImportEvent
        .active
        .joins(:import_source)
        .where(import_sources: { active: true, source_type: "easyticket" })
        .map do |record|
          ImportRecord.new(
            source: "easyticket",
            external_event_id: record.external_event_id,
            concert_date: record.concert_date,
            city: record.city,
            venue_name: record.venue_name,
            title: record.title,
            artist_name: record.artist_name,
            ticket_url: record.ticket_url,
            image_url: record.image_url,
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
        .joins(:import_source)
        .where(import_sources: { active: true, source_type: "eventim" })
        .map do |record|
          ImportRecord.new(
            source: "eventim",
            external_event_id: record.external_event_id,
            concert_date: record.concert_date,
            city: record.city,
            venue_name: record.venue_name,
            title: record.title,
            artist_name: record.artist_name,
            ticket_url: record.ticket_url,
            image_url: record.image_url,
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
      event.image_url = first_present(records, &:image_url)
      event.start_at = start_at_for(primary.concert_date)
      event.primary_source = primary.source
      event.source_snapshot = build_source_snapshot(records)
      updated_now = event.changed?

      offers = build_offer_attributes(records)
      completeness = Editorial::EventCompletenessChecker.new(event: event, offers: offers).call
      event.completeness_score = completeness.score
      event.completeness_flags = completeness.flags

      apply_status_rules(event, completeness)
      updated_now ||= event.changed?
      event.save! if created_now || updated_now

      offers_upserted = sync_offers!(event, offers)

      Editorial::EventChangeLogger.log!(
        event: event,
        action: created_now ? "merged_create" : "merged_update",
        user: nil,
        metadata: {
          source_types: records.map(&:source).uniq,
          external_event_ids: records.map(&:external_event_id)
        }
      )

      [ event, created_now, updated_now && !created_now, offers_upserted ]
    end

    def apply_status_rules(event, completeness)
      return if event.status == "rejected"
      return if event.published? && !event.auto_published?

      if completeness.ready_for_publish?
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

    def start_at_for(concert_date)
      Time.zone.local(concert_date.year, concert_date.month, concert_date.day, 20, 0, 0)
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
              "city" => record.city,
              "venue_name" => record.venue_name,
              "title" => record.title,
              "artist_name" => record.artist_name,
              "ticket_url" => record.ticket_url,
              "image_url" => record.image_url,
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
  end
end
