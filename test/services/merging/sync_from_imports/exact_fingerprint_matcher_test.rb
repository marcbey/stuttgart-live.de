require "test_helper"

class Merging::SyncFromImports::ExactFingerprintMatcherTest < ActiveSupport::TestCase
  test "finds an event by normalized_artist_name and exact start_at" do
    event = events(:published_one)
    matcher = Merging::SyncFromImports::ExactFingerprintMatcher.new(priority_map: Merging::ProviderPriorityMap.call)
    record = Merging::SyncFromImports::ImportRecord.new(
      source: "eventim",
      source_identifier: "record-1",
      external_event_id: "ext-1",
      series_reference: nil,
      artist_name: "Published Artist",
      title: "Published Event",
      start_at: event.start_at,
      doors_at: nil,
      city: nil,
      venue: "Other Venue",
      promoter_id: nil,
      promoter_name: nil,
      badge_text: nil,
      youtube_url: nil,
      homepage_url: nil,
      facebook_url: nil,
      event_info: nil,
      min_price: nil,
      max_price: nil,
      images: [],
      genre: nil,
      ticket_url: nil,
      ticket_price_text: nil,
      sold_out: false,
      raw_payload: {}
    )

    assert_equal event, matcher.call(record:)
  end
end
