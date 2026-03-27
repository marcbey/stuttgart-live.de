module Events
  module Retention
    class PrunePastRawEventImports
      Result = Data.define(:deleted_count, :deleted_by_source, :skipped_count, :cutoff_at)

      BATCH_SIZE = 250

      def self.call(...)
        new(...).call
      end

      def initialize(
        scope: RawEventImport.all,
        batch_size: BATCH_SIZE,
        logger: Rails.logger,
        now: Time.current,
        record_builder: Merging::SyncFromImports::RecordBuilder.new
      )
        @scope = scope
        @batch_size = batch_size
        @logger = logger
        @cutoff_at = normalize_now(now).advance(months: -1).beginning_of_day
        @record_builder = record_builder
      end

      def call
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

        result = Result.new(
          deleted_count: deleted_count,
          deleted_by_source: deleted_by_source.sort.to_h,
          skipped_count: skipped_count,
          cutoff_at: cutoff_at
        )
        log_result(result)
        result
      end

      private

      attr_reader :batch_size, :cutoff_at, :logger, :record_builder, :scope

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
          "deleted=#{result.deleted_count} skipped=#{result.skipped_count} " \
          "cutoff_at=#{result.cutoff_at.iso8601} deleted_by_source=#{result.deleted_by_source}"
        )
      end
    end
  end
end
