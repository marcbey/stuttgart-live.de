module Merging
  class SyncFromImports
    class RecordBuilder
      def build_record(raw_event_import)
        builder_for(raw_event_import).build
      end

      def import_records(last_run_at:)
        current_records = build_records(RawEventImport.latest_for)
        return current_records if last_run_at.blank?

        touched_fingerprints =
          build_records(
            RawEventImport.latest_for(
              RawEventImport.where("created_at >= ?", last_run_at)
            )
          ).map { |record| DuplicationKey.for_record(record) }.uniq

        return [] if touched_fingerprints.empty?

        current_records.select do |record|
          touched_fingerprints.include?(DuplicationKey.for_record(record))
        end
      end

      private

      def build_records(raw_event_imports)
        Array(raw_event_imports).filter_map do |raw_event_import|
          build_record(raw_event_import)
        end
      end

      def builder_for(raw_event_import)
        case raw_event_import.import_event_type
        when "easyticket"
          RecordBuilders::Easyticket.new(raw_event_import:)
        when "eventim"
          RecordBuilders::Eventim.new(raw_event_import:)
        when "reservix"
          RecordBuilders::Reservix.new(raw_event_import:)
        else
          raise ArgumentError, "Unsupported import source: #{raw_event_import.import_event_type.inspect}"
        end
      end
    end
  end
end
