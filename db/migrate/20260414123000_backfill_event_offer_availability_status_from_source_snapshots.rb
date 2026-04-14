class BackfillEventOfferAvailabilityStatusFromSourceSnapshots < ActiveRecord::Migration[8.1]
  class MigrationEvent < ApplicationRecord
    self.table_name = "events"

    has_many :event_offers, class_name: "BackfillEventOfferAvailabilityStatusFromSourceSnapshots::MigrationEventOffer", foreign_key: :event_id, inverse_of: :event
  end

  class MigrationEventOffer < ApplicationRecord
    self.table_name = "event_offers"

    belongs_to :event, class_name: "BackfillEventOfferAvailabilityStatusFromSourceSnapshots::MigrationEvent", inverse_of: :event_offers
  end

  CANCELED_EVENTIM_STATUS_CODES = %w[1].freeze

  def up
    say_with_time("Backfilling event offer availability statuses from source snapshots") do
      updated = 0

      MigrationEvent.includes(:event_offers).find_each do |event|
        normalized_sources = normalized_snapshot_sources(event.source_snapshot)
        next if normalized_sources.empty?

        event.event_offers.each do |offer|
          next unless offer.source.to_s == "eventim"

          source_snapshot = matching_source_snapshot(normalized_sources, offer)
          next if source_snapshot.blank?

          raw_payload = source_snapshot["raw_payload"].is_a?(Hash) ? source_snapshot["raw_payload"].deep_stringify_keys : {}
          source_status_code = raw_payload["eventStatus"].to_s.strip
          availability_status = availability_status_for(offer:, source_status_code:)

          metadata = offer.metadata.is_a?(Hash) ? offer.metadata.deep_stringify_keys : {}
          changed = false

          if availability_status.present? && metadata["availability_status"] != availability_status
            metadata["availability_status"] = availability_status
            changed = true
          end

          if source_status_code.present? && metadata["source_status_code"] != source_status_code
            metadata["source_status_code"] = source_status_code
            changed = true
          end

          next unless changed

          offer.update_columns(metadata:, updated_at: Time.current)
          updated += 1
        end
      end

      updated
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot restore previous event offer availability metadata"
  end

  private

  def normalized_snapshot_sources(source_snapshot)
    return [] unless source_snapshot.is_a?(Hash)

    Array(source_snapshot["sources"]).filter_map do |source|
      source.is_a?(Hash) ? source.deep_stringify_keys : nil
    end
  end

  def matching_source_snapshot(normalized_sources, offer)
    normalized_sources.find do |source|
      source["source"].to_s == offer.source.to_s &&
        source["external_event_id"].to_s == offer.source_event_id.to_s
    end
  end

  def availability_status_for(offer:, source_status_code:)
    return "canceled" if CANCELED_EVENTIM_STATUS_CODES.include?(source_status_code)
    return "sold_out" if offer.sold_out?

    "available"
  end
end
