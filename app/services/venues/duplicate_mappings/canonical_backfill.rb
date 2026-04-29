module Venues
  module DuplicateMappings
    class CanonicalBackfill
      def self.call(...)
        new(...).call
      end

      def initialize(mappings:, venue_scope: Venue.all, event_model: Event)
        @mappings = mappings
        @venue_scope = venue_scope
        @event_model = event_model
      end

      def call
        mappings_by_canonical_key.each_value do |canonical_mappings|
          backfill_canonical_venue(canonical_mappings)
        end
      end

      private

      attr_reader :event_model, :mappings, :venue_scope

      def mappings_by_canonical_key
        mappings
          .select { |mapping| mapping.fetch("canonical_key").present? }
          .group_by { |mapping| mapping.fetch("canonical_key") }
      end

      def backfill_canonical_venue(canonical_mappings)
        canonical = Venue.find_by_match_key(canonical_mappings.first.fetch("canonical_key"))
        return if canonical.present?

        canonical = Venue.create!(name: canonical_mappings.first.fetch("canonical"))
        copy_metadata!(canonical:, source: best_alias_venue_for(canonical_mappings))
      end

      def best_alias_venue_for(canonical_mappings)
        alias_keys = canonical_mappings.map { |mapping| mapping.fetch("alias_key") }

        venue_scope
          .includes(logo_attachment: [ :blob ])
          .to_a
          .select { |venue| alias_keys.include?(Venue.match_key(venue.name)) }
          .max_by { |venue| alias_venue_sort_key(venue) }
      end

      def alias_venue_sort_key(venue)
        [
          Venue.metadata_presence_count(venue),
          event_counts_by_venue_id.fetch(venue.id, 0),
          -venue.id.to_i
        ]
      end

      def copy_metadata!(canonical:, source:)
        return if source.blank?

        attributes = {}
        attributes[:description] = source.description if canonical.description.blank? && source.description.present?
        attributes[:external_url] = source.external_url if canonical.external_url.blank? && source.external_url.present?
        attributes[:address] = source.address if canonical.address.blank? && source.address.present?
        canonical.assign_attributes(attributes)
        canonical.logo.attach(source.logo.blob) if !canonical.logo.attached? && source.logo.attached?
        canonical.save! if canonical.changed?
      end

      def event_counts_by_venue_id
        @event_counts_by_venue_id ||= event_model.group(:venue_id).count
      end
    end
  end
end
