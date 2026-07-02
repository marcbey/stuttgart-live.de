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

  test "matches artist variants within the start time tolerance" do
    event = Event.create!(
      artist_name: "One Night of Taylor",
      title: "The Eras Experience",
      start_at: Time.zone.local(2026, 5, 13, 19, 0, 0),
      venue: "Liederhalle Beethoven-Saal",
      city: "Stuttgart",
      status: "needs_review",
      source_fingerprint: "matcher::one-night-of-taylor"
    )

    matcher = Merging::SyncFromImports::ArtistSimilarityMatcher.new(
      priority_map: Merging::ProviderPriorityMap.call,
      threshold: 0.74
    )

    record = build_record(
      "One Night of Taylor - The Eras Experience - Taylor Swift Tribute by Xenna",
      event.start_at + 1.hour
    )
    result = matcher.call(record:)

    assert_equal event, result&.event
    assert_equal "significant_tokens_subset", result&.reason
    assert_operator result&.score.to_f, :>=, 0.74
  end

  test "does not match artist variants outside the start time tolerance" do
    event = Event.create!(
      artist_name: "One Night of Taylor",
      title: "The Eras Experience",
      start_at: Time.zone.local(2026, 5, 13, 19, 0, 0),
      venue: "Liederhalle Beethoven-Saal",
      city: "Stuttgart",
      status: "needs_review",
      source_fingerprint: "matcher::one-night-of-taylor-outside-tolerance"
    )

    matcher = Merging::SyncFromImports::ArtistSimilarityMatcher.new(
      priority_map: Merging::ProviderPriorityMap.call,
      threshold: 0.74
    )

    record = build_record(
      "One Night of Taylor - The Eras Experience - Taylor Swift Tribute by Xenna",
      event.start_at + 1.hour + 1.minute
    )

    assert_nil matcher.call(record:)
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

  test "matches swapped artist and title names at the same start time" do
    event = Event.create!(
      artist_name: "Bitter",
      title: "Daniel Sloss",
      start_at: Time.zone.local(2026, 9, 22, 20, 0, 0),
      venue: "Theaterhaus - T1",
      city: "Stuttgart",
      status: "needs_review",
      source_fingerprint: "matcher::daniel-sloss-swapped"
    )

    matcher = Merging::SyncFromImports::ArtistSimilarityMatcher.new(
      priority_map: Merging::ProviderPriorityMap.call,
      threshold: 0.74
    )

    record = build_record("Daniel Sloss", event.start_at, title: "Bitter")
    result = matcher.call(record:)

    assert_equal event, result&.event
    assert_equal "artist_title_swap", result&.reason
    assert_operator result&.score.to_f, :>=, 0.74
  end

  test "matches swapped quoted tour titles at the same start time" do
    event = Event.create!(
      artist_name: "„Alpha Maus Tour 2026“",
      title: "Tara-Louise Wittwer",
      start_at: Time.zone.local(2026, 10, 5, 20, 0, 0),
      venue: "Theaterhaus - T1",
      city: "Stuttgart",
      status: "needs_review",
      source_fingerprint: "matcher::tara-louise-wittwer-swapped"
    )

    matcher = Merging::SyncFromImports::ArtistSimilarityMatcher.new(
      priority_map: Merging::ProviderPriorityMap.call,
      threshold: 0.74
    )

    record = build_record("Tara-Louise Wittwer", event.start_at, title: "Alpha Maus Tour 2026")
    result = matcher.call(record:)

    assert_equal event, result&.event
    assert_equal "artist_title_swap", result&.reason
    assert_operator result&.score.to_f, :>=, 0.74
  end

  test "does not match swapped names when only one cross comparison matches" do
    Event.create!(
      artist_name: "Daniel Sloss",
      title: "Bitter",
      start_at: Time.zone.local(2026, 9, 22, 20, 0, 0),
      venue: "Theaterhaus - T1",
      city: "Stuttgart",
      status: "needs_review",
      source_fingerprint: "matcher::one-sided-swap"
    )

    matcher = Merging::SyncFromImports::ArtistSimilarityMatcher.new(
      priority_map: Merging::ProviderPriorityMap.call,
      threshold: 0.74
    )

    record = build_record("Bitter", Time.zone.local(2026, 9, 22, 20, 0, 0), title: "Different Person")

    assert_nil matcher.call(record:)
  end

  test "does not match swapped names when an artist title pair is fallback-identical" do
    Event.create!(
      artist_name: "Daniel Sloss",
      title: "Daniel Sloss",
      start_at: Time.zone.local(2026, 9, 22, 20, 0, 0),
      venue: "Theaterhaus - T1",
      city: "Stuttgart",
      status: "needs_review",
      source_fingerprint: "matcher::fallback-identical-swap"
    )

    matcher = Merging::SyncFromImports::ArtistSimilarityMatcher.new(
      priority_map: Merging::ProviderPriorityMap.call,
      threshold: 0.74
    )

    record = build_record("Bitter", Time.zone.local(2026, 9, 22, 20, 0, 0), title: "Daniel Sloss")

    assert_nil matcher.call(record:)
  end

  private

  def build_record(artist_name, start_at, title: artist_name)
    Merging::SyncFromImports::ImportRecord.new(
      source: "eventim",
      raw_import_id: 1,
      raw_import_created_at: Time.zone.local(2026, 1, 1, 0, 0, 0),
      source_identifier: "#{artist_name.parameterize}:#{title.parameterize}:#{start_at.to_i}",
      external_event_id: SecureRandom.uuid,
      series_reference: nil,
      artist_name: artist_name,
      title: title,
      start_at: start_at,
      doors_at: nil,
      city: nil,
      venue: "Im Wizemann",
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
