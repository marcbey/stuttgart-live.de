require "test_helper"

class Merging::SyncFromImports::ExactFingerprintMatcherTest < ActiveSupport::TestCase
  test "finds an event by normalized_artist_name and exact start_at" do
    event = events(:published_one)
    matcher = Merging::SyncFromImports::ExactFingerprintMatcher.new(priority_map: Merging::ProviderPriorityMap.call)
    record = build_record(artist_name: "Published Artist", start_at: event.start_at)

    assert_equal event, matcher.call(record:)
  end

  test "finds an event by normalized_artist_name within the start_at tolerance" do
    event = events(:published_one)
    matcher = Merging::SyncFromImports::ExactFingerprintMatcher.new(priority_map: Merging::ProviderPriorityMap.call)
    record = build_record(artist_name: "Published Artist", start_at: event.start_at + 1.hour)

    assert_equal event, matcher.call(record:)
  end

  test "does not match an event outside the start_at tolerance" do
    event = events(:published_one)
    matcher = Merging::SyncFromImports::ExactFingerprintMatcher.new(priority_map: Merging::ProviderPriorityMap.call)
    record = build_record(artist_name: "Published Artist", start_at: event.start_at + 1.hour + 1.minute)

    assert_nil matcher.call(record:)
  end

  private

  def build_record(artist_name:, start_at:)
    Merging::SyncFromImports::ImportRecord.new(
      source: "eventim",
      raw_import_id: 1,
      raw_import_created_at: Time.zone.local(2026, 1, 1, 0, 0, 0),
      source_identifier: "record-1",
      external_event_id: "ext-1",
      series_reference: nil,
      artist_name: artist_name,
      title: "Published Event",
      start_at: start_at,
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
      availability_status: "available",
      raw_payload: {}
    )
  end
end
