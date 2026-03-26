require "test_helper"

class Public::VisibleEventsQueryTest < ActiveSupport::TestCase
  setup do
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: [ "10135", "10136", "382" ])
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.reset_cache!
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
  end

  test "filters to sks promoter ids" do
    matching_event = create_visible_event(title: "SKS Query", artist_name: "SKS Artist", promoter_id: AppSetting.sks_promoter_ids.first)
    create_visible_event(title: "Other Query", artist_name: "Other Artist", promoter_id: "99999")

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_SKS
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "includes manually highlighted events without sks promoter id" do
    sks_event = create_visible_event(title: "SKS Query", artist_name: "SKS Artist", promoter_id: AppSetting.sks_promoter_ids.first)
    highlighted_event = create_visible_event(title: "Manual Highlight", artist_name: "Manual Highlight Artist", promoter_id: "99999", highlighted: true)
    create_visible_event(title: "Other Query", artist_name: "Other Artist", promoter_id: "99999")

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_SKS
    ).call

    assert_equal [ sks_event, highlighted_event ], result.to_a
  end

  test "uses configured sks promoter ids" do
    AppSetting.find_by!(key: AppSetting::SKS_PROMOTER_IDS_KEY).update!(value: [ "77777" ])
    AppSetting.reset_cache!
    matching_event = create_visible_event(title: "Configured SKS Query", artist_name: "Configured Artist", promoter_id: "77777")
    create_visible_event(title: "Other SKS Query", artist_name: "Default Artist", promoter_id: "10135")

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_SKS
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "filters by event date and search query" do
    selected_date = 14.days.from_now.to_date
    matching_event = create_visible_event(
      title: "Irish Folk Night",
      artist_name: "The Query Band",
      start_at: selected_date.in_time_zone.change(hour: 20, min: 0, sec: 0)
    )
    create_visible_event(
      title: "Jazz Session",
      artist_name: "The Other Band",
      start_at: selected_date.in_time_zone.change(hour: 22, min: 0, sec: 0)
    )
    create_visible_event(
      title: "Irish Folk Night Late",
      artist_name: "The Query Band",
      start_at: (selected_date + 1.day).in_time_zone.change(hour: 20, min: 0, sec: 0)
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      event_date: selected_date,
      query: "irish"
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "matches german umlaut spellings via normalized query variants" do
    matching_event = create_visible_event(
      title: "Die Ärzte live",
      artist_name: "Die Ärzte"
    )
    create_visible_event(
      title: "Anderer Abend",
      artist_name: "Andere Band"
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: "Die Aerzte"
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "matches punctuation and repeated whitespace via normalized query variants" do
    matching_event = create_visible_event(
      title: "Live in Stuttgart",
      artist_name: "AC/DC"
    )
    create_visible_event(
      title: "Live in Stuttgart",
      artist_name: "AC and Friends"
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: " AC   DC   Live "
    ).call

    assert_equal [ matching_event ], result.to_a
  end

  test "ignores punctuation only queries" do
    create_visible_event(title: "First Event", artist_name: "First Artist")
    create_visible_event(title: "Second Event", artist_name: "Second Artist", start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0))

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: " ... !!! "
    ).call

    assert_equal Event.published_live.to_a, result.to_a
  end

  test "prioritizes sks events in search results" do
    regular_event = create_visible_event(
      title: "Search Priority Night",
      artist_name: "Regular Search Artist",
      promoter_id: "99999",
      start_at: 5.days.from_now.change(hour: 20, min: 0, sec: 0)
    )
    sks_event = create_visible_event(
      title: "Search Priority Night",
      artist_name: "SKS Search Artist",
      promoter_id: AppSetting.sks_promoter_ids.first,
      start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0)
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: "Search Priority"
    ).call

    assert_equal [ sks_event, regular_event ], result.to_a
  end

  test "prioritizes highlighted events in search results" do
    regular_event = create_visible_event(
      title: "Highlight Priority Night",
      artist_name: "Regular Highlight Artist",
      promoter_id: "99999",
      start_at: 5.days.from_now.change(hour: 20, min: 0, sec: 0)
    )
    highlighted_event = create_visible_event(
      title: "Highlight Priority Night",
      artist_name: "Highlighted Search Artist",
      promoter_id: "99999",
      highlighted: true,
      start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0)
    )

    result = Public::VisibleEventsQuery.new(
      scope: Event.published_live,
      filter: Public::VisibleEventsQuery::FILTER_ALL,
      query: "Highlight Priority"
    ).call

    assert_equal [ highlighted_event, regular_event ], result.to_a
  end

  private

  def create_visible_event(title:, artist_name:, promoter_id: nil, highlighted: false, start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0))
    Event.create!(
      title: title,
      artist_name: artist_name,
      start_at: start_at,
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: promoter_id,
      highlighted: highlighted,
      source_fingerprint: SecureRandom.uuid,
      source_snapshot: {}
    )
  end
end
