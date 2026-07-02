module Events
  module Maintenance
    class EventimTicketOfferRepairer
      Result = Data.define(
        :checked_events,
        :updated_events,
        :created_offers,
        :removed_stale_offers,
        :ignored_auxiliary_records,
        :ambiguous_events,
        :dry_run,
        :series_summaries
      )

      def self.call(...)
        new(...).call
      end

      def initialize(
        dry_run: false,
        event_relation: default_event_relation,
        raw_import_relation: RawEventImport.where(import_event_type: "eventim")
      )
        @dry_run = dry_run
        @event_relation = event_relation
        @raw_import_relation = raw_import_relation
        @priority_map = Merging::ProviderPriorityMap.call
        @record_builder = Merging::SyncFromImports::RecordBuilder.new
        @checked_events = 0
        @updated_events = 0
        @created_offers = 0
        @removed_stale_offers = 0
        @ignored_auxiliary_records = 0
        @ambiguous_events = 0
        @series_summaries = {}
      end

      def call
        event_relation.includes(:event_offers, :event_series).find_each do |event|
          repair_event(event)
        end

        Result.new(
          checked_events: @checked_events,
          updated_events: @updated_events,
          created_offers: @created_offers,
          removed_stale_offers: @removed_stale_offers,
          ignored_auxiliary_records: @ignored_auxiliary_records,
          ambiguous_events: @ambiguous_events,
          dry_run: dry_run?,
          series_summaries: @series_summaries
        )
      end

      private

      attr_reader :event_relation, :priority_map, :raw_import_relation, :record_builder

      def self.default_event_relation
        Event.joins(:event_offers)
          .where(event_offers: { source: "eventim" })
          .distinct
      end

      def default_event_relation
        self.class.default_event_relation
      end

      def dry_run?
        @dry_run
      end

      def repair_event(event)
        @checked_events += 1
        increment_series(event, "checked_events")

        records = import_records_for(event)
        return if records.empty?

        if ambiguous_records?(records)
          @ambiguous_events += 1
          increment_series(event, "ambiguous_events")
          return
        end

        desired_records = Merging::SyncFromImports::EventimOfferConsolidator.call(records)
        desired_attributes = desired_records.index_by(&:external_event_id).transform_values do |record|
          offer_attributes_for(record)
        end
        desired_ids = desired_attributes.keys.map(&:to_s)
        existing_eventim_offers = event.event_offers.select { |offer| offer.source.to_s == "eventim" }
        existing_by_source_event_id = existing_eventim_offers.index_by { |offer| offer.source_event_id.to_s }
        offers_to_remove = existing_eventim_offers.reject { |offer| desired_ids.include?(offer.source_event_id.to_s) }
        attributes_to_create = desired_attributes.reject { |source_event_id, _attrs| existing_by_source_event_id.key?(source_event_id.to_s) }
        attributes_to_update = desired_attributes.filter_map do |source_event_id, attrs|
          offer = existing_by_source_event_id[source_event_id.to_s]
          next if offer.blank?
          next unless offer_needs_update?(offer, attrs)

          [ offer, attrs ]
        end

        ignored_auxiliary_count = ignored_auxiliary_records_count(records, desired_records)
        changed = offers_to_remove.any? || attributes_to_create.any? || attributes_to_update.any?
        return unless changed

        @updated_events += 1
        @created_offers += attributes_to_create.size
        @removed_stale_offers += offers_to_remove.size
        @ignored_auxiliary_records += ignored_auxiliary_count
        increment_series(event, "updated_events")
        increment_series(event, "created_offers", attributes_to_create.size)
        increment_series(event, "removed_stale_offers", offers_to_remove.size)
        increment_series(event, "ignored_auxiliary_records", ignored_auxiliary_count)

        return if dry_run?

        ActiveRecord::Base.transaction do
          attributes_to_create.each_value { |attrs| event.event_offers.create!(attrs) }
          attributes_to_update.each { |offer, attrs| offer.update!(attrs) }
          offers_to_remove.each(&:destroy!)
        end
      end

      def import_records_for(event)
        source_identifiers_for(event).filter_map do |source_identifier|
          raw_import = raw_imports_by_source_identifier[source_identifier]
          record_builder.build_record(raw_import) if raw_import.present?
        end.uniq(&:external_event_id)
      end

      def source_identifiers_for(event)
        identifiers = []
        event_date = event.start_at&.to_date&.iso8601

        event.event_offers.each do |offer|
          next unless offer.source.to_s == "eventim"

          source_event_id = offer.source_event_id.to_s.strip
          next if source_event_id.blank?

          identifiers << source_event_id
          identifiers << "#{source_event_id}:#{event_date}" if event_date.present?
        end

        eventim_snapshot_sources(event).each do |source|
          source_identifier = source["source_identifier"].to_s.strip
          external_event_id = source["external_event_id"].to_s.strip
          identifiers << source_identifier if source_identifier.present?
          identifiers << external_event_id if external_event_id.present?
          identifiers << "#{external_event_id}:#{event_date}" if external_event_id.present? && event_date.present?
        end

        identifiers.uniq
      end

      def eventim_snapshot_sources(event)
        snapshot = event.source_snapshot.is_a?(Hash) ? event.source_snapshot : {}
        Array(snapshot["sources"]).select { |source| source.is_a?(Hash) && source["source"].to_s == "eventim" }
      end

      def raw_imports_by_source_identifier
        @raw_imports_by_source_identifier ||=
          RawEventImport.latest_for(raw_import_relation).index_by(&:source_identifier)
      end

      def ambiguous_records?(records)
        identity_keys = records.filter_map { |record| eventim_classification(record).identity_key }.uniq

        records.size > 1 && identity_keys.size != 1
      end

      def ignored_auxiliary_records_count(records, desired_records)
        desired_ids = desired_records.map { |record| record.external_event_id.to_s }.to_set
        records.count do |record|
          !desired_ids.include?(record.external_event_id.to_s) &&
            eventim_classification(record).kind == "auxiliary"
        end
      end

      def offer_needs_update?(offer, attrs)
        attrs.except(:metadata).any? do |key, value|
          offer.public_send(key) != value
        end
      end

      def offer_attributes_for(record)
        {
          source: record.source,
          source_event_id: record.external_event_id,
          ticket_url: record.ticket_url,
          ticket_price_text: record.ticket_price_text,
          sold_out: record.sold_out,
          priority_rank: priority_map.fetch(record.source, 999),
          metadata: offer_metadata_for(record)
        }
      end

      def offer_metadata_for(record)
        metadata = {}
        metadata["min_price"] = record.min_price.to_s("F") if record.min_price.present?
        metadata["max_price"] = record.max_price.to_s("F") if record.max_price.present?
        metadata["availability_status"] = record.availability_status if record.availability_status.present?
        metadata["source_status_code"] = record.raw_payload["eventStatus"].to_s.strip if record.raw_payload["eventStatus"].present?
        metadata["raw_import_id"] = record.raw_import_id if record.raw_import_id.present?
        metadata["raw_import_created_at"] = record.raw_import_created_at&.iso8601 if record.raw_import_created_at.present?

        classification = eventim_classification(record)
        metadata["eventim_series_id"] = classification.series_id if classification.series_id.present?
        metadata["eventim_series_name"] = classification.series_name if classification.series_name.present?
        metadata["eventim_offer_kind"] = classification.kind
        metadata
      end

      def eventim_classification(record)
        @eventim_classifications ||= {}
        @eventim_classifications[record.external_event_id] ||= Importing::Eventim::TicketOfferClassifier.call(record)
      end

      def increment_series(event, key, amount = 1)
        summary = @series_summaries[series_name_for(event)] ||= {
          "checked_events" => 0,
          "updated_events" => 0,
          "created_offers" => 0,
          "removed_stale_offers" => 0,
          "ignored_auxiliary_records" => 0,
          "ambiguous_events" => 0
        }
        summary[key] += amount
      end

      def series_name_for(event)
        event.event_series&.name.to_s.strip.presence || "Ohne Event-Reihe"
      end
    end
  end
end
