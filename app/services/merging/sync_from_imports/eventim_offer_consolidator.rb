module Merging
  class SyncFromImports
    class EventimOfferConsolidator
      def self.call(records)
        new(records).call
      end

      def initialize(records)
        @records = Array(records)
      end

      def call
        other_records + consolidated_eventim_records
      end

      private

      attr_reader :records

      def other_records
        records.reject { |record| eventim?(record) }
      end

      def eventim_records
        records.select { |record| eventim?(record) }
      end

      def consolidated_eventim_records
        eventim_records.group_by { |record| consolidation_key(record) }.values.flat_map do |group|
          consolidate_group(group)
        end
      end

      def consolidate_group(group)
        return group if group.size == 1

        classified_records = group.map { |record| [ record, classify(record) ] }
        main_records = classified_records.filter_map do |record, classification|
          record if classification.kind == "main"
        end

        return [ newest_record(main_records) ] if main_records.any?

        group
      end

      def newest_record(group)
        group.max_by do |record|
          [
            record.raw_import_created_at || Time.zone.at(0),
            record.raw_import_id.to_i
          ]
        end
      end

      def consolidation_key(record)
        classification = classify(record)
        return [ :identity, classification.identity_key ] if classification.identity_key.present?

        [ :source_event_id, record.external_event_id.to_s ]
      end

      def classify(record)
        Importing::Eventim::TicketOfferClassifier.call(record)
      end

      def eventim?(record)
        record.source.to_s == "eventim"
      end
    end
  end
end
