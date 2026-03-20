module Merging
  class SyncFromImports
    Result = Data.define(
      :import_records_count,
      :groups_count,
      :events_created_count,
      :events_updated_count,
      :duplicate_matches_count,
      :offers_upserted_count,
      :canceled
    )

    ImportRecord = Data.define(
      :source,
      :source_identifier,
      :external_event_id,
      :artist_name,
      :title,
      :start_at,
      :doors_at,
      :city,
      :venue,
      :promoter_id,
      :badge_text,
      :youtube_url,
      :homepage_url,
      :facebook_url,
      :event_info,
      :min_price,
      :max_price,
      :images,
      :genre,
      :ticket_url,
      :ticket_price_text,
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

    StopRequested = Class.new(StandardError)

    def initialize(merge_run_id: nil, last_run_at: nil, logger: Rails.logger, progress_callback: nil, stop_requested_callback: nil)
      @merge_run_id = merge_run_id
      @last_run_at = normalize_last_run_at(last_run_at)
      @logger = logger
      @progress_callback = progress_callback
      @stop_requested_callback = stop_requested_callback
      @priority_map = ProviderPriorityMap.call
      @record_builder = RecordBuilder.new
      @match_strategy = MatchStrategy.new(priority_map: @priority_map)
      @event_upserter = EventUpserter.new(
        merge_run_id: @merge_run_id,
        logger: @logger,
        priority_map: @priority_map,
        match_strategy: @match_strategy
      )
    end

    def call
      records = record_builder.import_records(last_run_at: last_run_at)
      groups = records.group_by { |record| fingerprint_for(record) }

      created = 0
      updated = 0
      duplicates = 0
      offers_upserted = 0

      report_progress!(
        import_records_count: records.size,
        groups_count: groups.count,
        events_created_count: created,
        events_updated_count: updated,
        duplicate_matches_count: duplicates,
        offers_upserted_count: offers_upserted,
        processed_groups_count: 0
      )
      stop_if_requested!

      ActiveRecord::Base.transaction do
        groups.each_value.with_index(1) do |group_records, processed_groups_count|
          stop_if_requested!

          ordered_records = ordered_records_for_group(group_records)
          _event, created_now, updated_now, duplicate_now, offers_count = event_upserter.call(ordered_records)
          created += 1 if created_now
          updated += 1 if updated_now
          duplicates += 1 if duplicate_now
          offers_upserted += offers_count

          report_progress!(
            import_records_count: records.size,
            groups_count: groups.count,
            events_created_count: created,
            events_updated_count: updated,
            duplicate_matches_count: duplicates,
            offers_upserted_count: offers_upserted,
            processed_groups_count: processed_groups_count
          )
        end
      end

      Result.new(
        import_records_count: records.size,
        groups_count: groups.count,
        events_created_count: created,
        events_updated_count: updated,
        duplicate_matches_count: duplicates,
        offers_upserted_count: offers_upserted,
        canceled: false
      )
    rescue StopRequested
      Result.new(
        import_records_count: records.size,
        groups_count: groups.count,
        events_created_count: 0,
        events_updated_count: 0,
        duplicate_matches_count: 0,
        offers_upserted_count: 0,
        canceled: true
      )
    end

    private

    attr_reader :event_upserter, :last_run_at, :logger, :priority_map, :progress_callback, :record_builder, :stop_requested_callback

    def ordered_records_for_group(records)
      records.sort_by do |record|
        [
          priority_for(record.source),
          record.source.to_s,
          record.source_identifier.to_s,
          record.external_event_id.to_s
        ]
      end
    end

    def fingerprint_for(record)
      DuplicationKey.for_record(record)
    end

    def normalize_last_run_at(value)
      return value.in_time_zone if value.respond_to?(:in_time_zone)

      raw_value = value.to_s.strip
      return nil if raw_value.blank?

      Time.zone.parse(raw_value)
    rescue ArgumentError
      nil
    end

    def priority_for(source)
      priority_map.fetch(source, 999)
    end

    def report_progress!(attributes)
      progress_callback&.call(attributes)
    end

    def stop_if_requested!
      raise StopRequested if stop_requested_callback&.call
    end
  end
end
