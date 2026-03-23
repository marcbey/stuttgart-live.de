require "test_helper"

class Merging::SyncFromImports::MatchStrategyTest < ActiveSupport::TestCase
  test "uses exact matcher when similarity matching is disabled" do
    AppSetting.create!(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY, value: false)
    AppSetting.reset_cache!

    event = Event.create!(
      artist_name: "Band X",
      title: "Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review",
      source_fingerprint: "match-strategy::bandx"
    )

    strategy = Merging::SyncFromImports::MatchStrategy.new(priority_map: Merging::ProviderPriorityMap.call)
    result = strategy.call(records: [ build_record("Band X", event.start_at, "source-1") ])

    assert_equal event, result&.event
    assert_equal "exact_fingerprint", result&.reason
  end

  test "uses similarity matcher when enabled and exact match misses" do
    AppSetting.create!(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY, value: true)
    AppSetting.reset_cache!

    event = Event.create!(
      artist_name: "Vier Pianisten",
      title: "Konzertabend",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review",
      source_fingerprint: "match-strategy::vierpianisten"
    )

    strategy = Merging::SyncFromImports::MatchStrategy.new(priority_map: Merging::ProviderPriorityMap.call)
    result = strategy.call(records: [ build_record("Vier Pianisten - Ein Konzert", event.start_at, "source-2") ])

    assert_equal event, result&.event
    assert_equal "significant_tokens_exact", result&.reason
  end

  private

  def build_record(artist_name, start_at, external_event_id)
    Merging::SyncFromImports::ImportRecord.new(
      source: "eventim",
      source_identifier: "#{artist_name.parameterize}:#{external_event_id}",
      external_event_id: external_event_id,
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
