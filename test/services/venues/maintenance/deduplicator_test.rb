require "test_helper"

module Venues
  module Maintenance
    class DeduplicatorTest < ActiveSupport::TestCase
      test "merges duplicate venues, reassigns events, and keeps the canonical venue" do
        canonical = Venue.create!(name: "Porsche-Arena")
        duplicate = Venue.create!(
          name: "Porsche-Arena Stuttgart",
          description: "Mehrzweckhalle in Stuttgart",
          external_url: "https://porsche-arena.example",
          address: "Mercedesstraße 69, 70372 Stuttgart"
        )
        duplicate.logo.attach(create_uploaded_blob(filename: "porsche-arena.png"))

        event_one = create_event_for(venue: duplicate, title: "Arena Show")
        event_two = create_event_for(venue: duplicate, title: "Arena Late Show", start_at: 2.days.from_now.change(usec: 0))

        result = Deduplicator.call(venue_scope: Venue.where(id: [ canonical.id, duplicate.id ]))

        assert_equal 1, result.groups
        assert_equal 1, result.venues_merged
        assert_equal 2, result.events_reassigned
        assert_equal 1, result.venues_deleted

        assert_not Venue.exists?(duplicate.id)

        canonical.reload
        assert_equal "Mehrzweckhalle in Stuttgart", canonical.description
        assert_equal "https://porsche-arena.example", canonical.external_url
        assert_equal "Mercedesstraße 69, 70372 Stuttgart", canonical.address
        assert canonical.logo.attached?

        assert_equal canonical.id, event_one.reload.venue_id
        assert_equal canonical.id, event_two.reload.venue_id
      end

      private

      def create_event_for(venue:, title:, start_at: 1.day.from_now.change(usec: 0))
        Event.create!(
          artist_name: "#{title} Artist",
          title:,
          start_at:,
          venue_record: venue,
          city: "Stuttgart",
          status: "needs_review"
        )
      end
    end
  end
end
