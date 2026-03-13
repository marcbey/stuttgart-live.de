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
      :promoter_id,
      :description_text,
      :ticket_url,
      :ticket_price_text,
      :min_price,
      :max_price,
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
      @record_builder = RecordBuilder.new(priority_map: @priority_map)
      @event_upserter = EventUpserter.new(
        merge_run_id: @merge_run_id,
        logger: @logger,
        priority_map: @priority_map
      )
    end

    def call
      records = record_builder.import_records
      groups = records.group_by { |record| fingerprint_for(record) }

      created = 0
      updated = 0
      offers_upserted = 0

      ActiveRecord::Base.transaction do
        groups.each_value do |records|
          ordered_records = ordered_records_for_group(records)
          _event, created_now, updated_now, offers_count = event_upserter.call(ordered_records)
          created += 1 if created_now
          updated += 1 if updated_now
          offers_upserted += offers_count
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

    attr_reader :event_upserter, :logger, :priority_map, :record_builder

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
      DuplicationKey.for_record(record)
    end

    def priority_for(source)
      priority_map.fetch(source, 999)
    end
  end
end
