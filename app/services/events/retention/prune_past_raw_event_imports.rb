module Events
  module Retention
    class PrunePastRawEventImports
      Result = Data.define(
        :deleted_count,
        :deleted_by_source,
        :skipped_count,
        :cutoff_at,
        :deleted_past_event_count,
        :deleted_superseded_count,
        :superseded_cutoff_at,
        :superseded_delete_limit_reached
      )
      DeletionResult = Data.define(:deleted_count, :deleted_by_source, :skipped_count, :limit_reached)

      BATCH_SIZE = 250
      SUPERSEDED_RETENTION = 14.days
      SUPERSEDED_DELETE_LIMIT = 50_000

      def self.call(...)
        new(...).call
      end

      def initialize(
        scope: RawEventImport.all,
        batch_size: BATCH_SIZE,
        logger: Rails.logger,
        now: Time.current,
        record_builder: Merging::SyncFromImports::RecordBuilder.new,
        superseded_retention: SUPERSEDED_RETENTION,
        superseded_delete_limit: SUPERSEDED_DELETE_LIMIT
      )
        @scope = scope
        @batch_size = batch_size
        @logger = logger
        @now = normalize_now(now)
        @cutoff_at = @now.advance(months: -1).beginning_of_day
        @superseded_cutoff_at = @now - superseded_retention
        @superseded_delete_limit = superseded_delete_limit.to_i
        @record_builder = record_builder
      end

      def call
        superseded_result = prune_superseded_raw_event_imports
        past_event_result = prune_past_event_raw_event_imports

        result = Result.new(
          deleted_count: superseded_result.deleted_count + past_event_result.deleted_count,
          deleted_by_source: merged_deleted_by_source(superseded_result, past_event_result),
          skipped_count: past_event_result.skipped_count,
          cutoff_at: cutoff_at,
          deleted_past_event_count: past_event_result.deleted_count,
          deleted_superseded_count: superseded_result.deleted_count,
          superseded_cutoff_at: superseded_cutoff_at,
          superseded_delete_limit_reached: superseded_result.limit_reached
        )
        log_result(result)
        result
      end

      private

      attr_reader :batch_size,
        :cutoff_at,
        :logger,
        :record_builder,
        :scope,
        :superseded_cutoff_at,
        :superseded_delete_limit

      def prune_superseded_raw_event_imports
        deleted_by_source = Hash.new(0)
        deleted_count = 0
        remaining_limit = superseded_delete_limit
        limit_reached = false

        while remaining_limit.positive?
          rows = superseded_raw_event_import_rows(limit: [ batch_size, remaining_limit ].min)
          break if rows.empty?

          RawEventImport.where(id: rows.map { |row| row.fetch("id") }).delete_all
          rows.each { |row| deleted_by_source[row.fetch("import_event_type")] += 1 }
          deleted_count += rows.size
          remaining_limit -= rows.size

          next if remaining_limit.positive?

          limit_reached = superseded_raw_event_import_rows(limit: 1).any?
        end

        if superseded_delete_limit <= 0
          limit_reached = superseded_raw_event_import_rows(limit: 1).any?
        end

        DeletionResult.new(
          deleted_count: deleted_count,
          deleted_by_source: deleted_by_source.sort.to_h,
          skipped_count: 0,
          limit_reached: limit_reached
        )
      end

      def prune_past_event_raw_event_imports
        deleted_by_source = Hash.new(0)
        deleted_count = 0
        skipped_count = 0

        scope.find_each(batch_size: batch_size) do |raw_event_import|
          import_record = build_record(raw_event_import)

          if import_record.blank? || import_record.start_at.blank?
            skipped_count += 1
            next
          end

          next unless import_record.start_at < cutoff_at

          deleted_by_source[raw_event_import.import_event_type] += 1
          raw_event_import.destroy!
          deleted_count += 1
        end

        DeletionResult.new(
          deleted_count: deleted_count,
          deleted_by_source: deleted_by_source.sort.to_h,
          skipped_count: skipped_count,
          limit_reached: false
        )
      end

      def superseded_raw_event_import_rows(limit:)
        return [] unless limit.positive?

        RawEventImport.connection.exec_query(
          RawEventImport.sanitize_sql_array([
            <<~SQL.squish,
              SELECT old.id, old.import_event_type
              FROM (#{superseded_candidate_scope.to_sql}) old
              WHERE old.created_at < ?
                AND EXISTS (
                  SELECT 1
                  FROM #{RawEventImport.quoted_table_name} newer
                  WHERE newer.import_event_type = old.import_event_type
                    AND newer.source_identifier = old.source_identifier
                    AND (newer.created_at, newer.id) > (old.created_at, old.id)
                )
              ORDER BY old.id
              LIMIT ?
            SQL
            superseded_cutoff_at,
            limit
          ])
        ).to_a
      end

      def superseded_candidate_scope
        scope
          .unscope(:select, :order)
          .select(:id, :import_event_type, :source_identifier, :created_at)
      end

      def merged_deleted_by_source(*results)
        results.each_with_object(Hash.new(0)) do |result, merged|
          result.deleted_by_source.each { |source, count| merged[source] += count }
        end.sort.to_h
      end

      def build_record(raw_event_import)
        record_builder.build_record(raw_event_import)
      rescue StandardError => error
        logger.warn(
          "[Events::Retention::PrunePastRawEventImports] " \
          "skipping_raw_event_import_id=#{raw_event_import.id} " \
          "source=#{raw_event_import.import_event_type} error=#{error.class}: #{error.message}"
        )
        nil
      end

      def normalize_now(value)
        value.respond_to?(:in_time_zone) ? value.in_time_zone : Time.zone.parse(value.to_s)
      rescue ArgumentError
        Time.current
      end

      def log_result(result)
        logger.info(
          "[Events::Retention::PrunePastRawEventImports] " \
          "deleted=#{result.deleted_count} deleted_superseded=#{result.deleted_superseded_count} " \
          "deleted_past_event=#{result.deleted_past_event_count} skipped=#{result.skipped_count} " \
          "cutoff_at=#{result.cutoff_at.iso8601} " \
          "superseded_cutoff_at=#{result.superseded_cutoff_at.iso8601} " \
          "superseded_delete_limit_reached=#{result.superseded_delete_limit_reached} " \
          "deleted_by_source=#{result.deleted_by_source}"
        )
      end
    end
  end
end
