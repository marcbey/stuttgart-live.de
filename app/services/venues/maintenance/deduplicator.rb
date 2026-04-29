module Venues
  module Maintenance
    class Deduplicator
      Result = Data.define(:groups, :venues_merged, :events_reassigned, :venues_deleted)

      def self.call(...)
        new(...).call
      end

      def initialize(venue_scope: Venue.all, event_model: Event, clock: -> { Time.current })
        @venue_scope = venue_scope
        @event_model = event_model
        @clock = clock
      end

      def call
        result = Result.new(groups: 0, venues_merged: 0, events_reassigned: 0, venues_deleted: 0)

        duplicate_groups.each do |group|
          canonical = canonical_venue_for(group)
          duplicates = group.reject { |venue| venue.id == canonical.id }
          next if duplicates.empty?

          duplicates.each do |duplicate|
            result = merge_duplicate!(result, canonical:, duplicate:)
          end

          result = increment_result(result, :groups, 1)
        end

        result
      end

      private

      attr_reader :clock, :event_model, :venue_scope

      def duplicate_groups
        venue_scope
          .includes(logo_attachment: [ :blob ])
          .to_a
          .group_by { |venue| Venue.canonical_match_key(venue.name) }
          .values
          .select { |venues| venues.size > 1 }
      end

      def canonical_venue_for(group)
        group.min_by do |venue|
          [
            Venue.stuttgart_suffix?(venue.name) ? 1 : 0,
            -Venue.metadata_presence_count(venue),
            -event_counts_by_venue_id.fetch(venue.id, 0),
            venue.id
          ]
        end
      end

      def merge_duplicate!(result, canonical:, duplicate:)
        ActiveRecord::Base.transaction do
          reassign_count = reassign_events!(canonical:, duplicate:)
          merge_blank_metadata!(canonical:, duplicate:)
          transfer_logo!(canonical:, duplicate:)
          duplicate.destroy!

          result = increment_result(result, :venues_merged, 1)
          result = increment_result(result, :venues_deleted, 1)
          result = increment_result(result, :events_reassigned, reassign_count)
        end

        result
      end

      def reassign_events!(canonical:, duplicate:)
        event_model.where(venue_id: duplicate.id).update_all(venue_id: canonical.id, updated_at: clock.call)
      end

      def merge_blank_metadata!(canonical:, duplicate:)
        attributes = {}
        attributes[:description] = duplicate.description if canonical.description.blank? && duplicate.description.present?
        attributes[:external_url] = duplicate.external_url if canonical.external_url.blank? && duplicate.external_url.present?
        attributes[:address] = duplicate.address if canonical.address.blank? && duplicate.address.present?
        return if attributes.empty?

        canonical.update!(attributes)
      end

      def transfer_logo!(canonical:, duplicate:)
        return if canonical.logo.attached?
        return unless duplicate.logo.attached?

        canonical.logo.attach(duplicate.logo.blob)
      end

      def event_counts_by_venue_id
        @event_counts_by_venue_id ||= event_model.group(:venue_id).count
      end

      def increment_result(result, key, amount)
        Result.new(
          groups: result.groups + (key == :groups ? amount : 0),
          venues_merged: result.venues_merged + (key == :venues_merged ? amount : 0),
          events_reassigned: result.events_reassigned + (key == :events_reassigned ? amount : 0),
          venues_deleted: result.venues_deleted + (key == :venues_deleted ? amount : 0)
        )
      end
    end
  end
end
