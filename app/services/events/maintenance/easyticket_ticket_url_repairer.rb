module Events
  module Maintenance
    class EasyticketTicketUrlRepairer
      Result = Data.define(
        :checked_count,
        :updated_count,
        :unchanged_count,
        :missing_raw_import_count,
        :blank_expected_url_count,
        :dry_run
      )

      def self.call(...)
        new(...).call
      end

      def initialize(
        dry_run: false,
        offer_relation: EventOffer.where(source: "easyticket"),
        raw_import_relation: RawEventImport.where(import_event_type: "easyticket")
      )
        @dry_run = dry_run
        @offer_relation = offer_relation
        @raw_import_relation = raw_import_relation
        @updated_count = 0
        @unchanged_count = 0
        @missing_raw_import_count = 0
        @blank_expected_url_count = 0
      end

      def call
        offers = offer_relation.includes(:event).order(:id).to_a

        offers.each do |offer|
          raw_import = raw_import_for(offer)

          if raw_import.nil?
            @missing_raw_import_count += 1
            next
          end

          expected_url = expected_ticket_url_for(raw_import)

          if expected_url.blank?
            @blank_expected_url_count += 1
            next
          end

          if offer.ticket_url.to_s == expected_url
            @unchanged_count += 1
            next
          end

          offer.update!(ticket_url: expected_url) unless dry_run?
          @updated_count += 1
        end

        Result.new(
          checked_count: offers.size,
          updated_count: @updated_count,
          unchanged_count: @unchanged_count,
          missing_raw_import_count: @missing_raw_import_count,
          blank_expected_url_count: @blank_expected_url_count,
          dry_run: dry_run?
        )
      end

      private

      attr_reader :offer_relation, :raw_import_relation

      def dry_run?
        @dry_run
      end

      def raw_import_for(offer)
        source_identifier = source_identifier_for(offer)
        raw_imports_by_source_identifier[source_identifier] if source_identifier.present?
      end

      def source_identifier_for(offer)
        return if offer.source_event_id.blank? || offer.event&.start_at.blank?

        "#{offer.source_event_id}:#{offer.event.start_at.to_date.iso8601}"
      end

      def raw_imports_by_source_identifier
        @raw_imports_by_source_identifier ||=
          RawEventImport.latest_for(raw_import_relation).index_by(&:source_identifier)
      end

      def expected_ticket_url_for(raw_import)
        record = Merging::SyncFromImports::RecordBuilders::Easyticket
          .new(raw_event_import: raw_import)
          .build

        record&.ticket_url.to_s
      end
    end
  end
end
