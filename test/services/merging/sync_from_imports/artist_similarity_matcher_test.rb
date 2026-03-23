require "test_helper"

class Merging::SyncFromImports::ArtistSimilarityMatcherTest < ActiveSupport::TestCase
  test "matches orchestra suffix names at the same start time" do
    event = Event.create!(
      artist_name: "Gregory Porter",
      title: "Jazz Night",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review",
      source_fingerprint: "matcher::gregoryporter"
    )

    matcher = Merging::SyncFromImports::ArtistSimilarityMatcher.new(
      priority_map: Merging::ProviderPriorityMap.call,
      threshold: 0.74
    )

    record = build_record("Gregory Porter & Orchestra", event.start_at)
    result = matcher.call(record:)

    assert_equal event, result&.event
    assert_operator result&.score.to_f, :>=, 0.74
  end

  test "does not match clearly different artists" do
    Event.create!(
      artist_name: "Band Alpha",
      title: "Alpha Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review",
      source_fingerprint: "matcher::alpha"
    )

    matcher = Merging::SyncFromImports::ArtistSimilarityMatcher.new(
      priority_map: Merging::ProviderPriorityMap.call,
      threshold: 0.74
    )

    assert_nil matcher.call(record: build_record("Band Beta", Time.zone.local(2026, 10, 10, 20, 0, 0)))
  end

  private

  def build_record(artist_name, start_at)
    Merging::SyncFromImports::ImportRecord.new(
      source: "eventim",
      source_identifier: "#{artist_name.parameterize}:#{start_at.to_i}",
      external_event_id: SecureRandom.uuid,
      series_reference: nil,
      artist_name: artist_name,
      title: artist_name,
      start_at: start_at,
      doors_at: nil,
      city: nil,
      venue: "Im Wizemann",
      promoter_id: nil,
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
      raw_payload: {}
    )
  end
end
