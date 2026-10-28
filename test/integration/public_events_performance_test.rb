require "test_helper"

class PublicEventsPerformanceTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12, 0, 0)
    @event = events(:published_one)
    @event.update!(highlighted: true, min_price: 20)
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.reset_cache!
    travel_back
  end

  test "event details do not query unused homepage price lanes" do
    queries = capture_queries { get event_url(@event.slug) }

    assert_response :success
    assert_includes response.body, @event.artist_name
    assert_select ".design-preview-header-genres a", minimum: 1
    assert_equal 0, queries.count { |sql| sql.include?("events.min_price <=") }, "Unused homepage price queries"
  end

  test "event lists do not query unused homepage price lanes and retain today's tips" do
    today = @event.dup
    today.assign_attributes(
      slug: "performance-todays-tip",
      source_fingerprint: "test::performance::todays-tip",
      artist_name: "Today's Tip Artist",
      start_at: Time.current.change(hour: 20)
    )
    today.save!

    queries = capture_queries { get all_stuttgart_lane_url(event_month: "2026-06") }

    assert_response :success
    assert_select ".design-preview-card-title", text: today.artist_name
    assert_includes response.body, @event.artist_name
    assert_equal 0, queries.count { |sql| sql.include?("events.min_price <=") }, "Unused homepage price queries"
  end

  test "event list filters select metadata without joining image and offer data" do
    queries = capture_queries { get all_stuttgart_lane_url(event_month: "2026-06") }
    metadata_queries = queries.grep(/\ASELECT (?:DISTINCT )?(?:"events"\."start_at"|"genres"\."id"|"venues"\."name")/)

    assert_response :success
    assert_includes response.body, @event.artist_name
    assert_not_empty metadata_queries
    metadata_queries.each do |sql|
      joins_media = sql.match?(/JOIN "(?:event_images|import_event_images|active_storage_\w+|event_offers)"/)
      refute joins_media, "Filter metadata unnecessarily joins image or offer tables"
    end
  end

  test "mix calculates series badges only for the rendered cards as genres increase" do
    EventGenre.delete_all
    groups = [ genres(:rock), genres(:pop), genres(:metal), genres(:jazz) ]

    [ 2, 4 ].each do |group_count|
      ((group_count - 2)...group_count).each do |index|
        series = EventSeries.create!(origin: "manual", name: "Mix Series #{index}")
        2.times do |term|
          event = @event.dup
          event.assign_attributes(
            slug: "mix-series-#{index}-#{term}",
            source_fingerprint: "test::mix-series::#{index}::#{term}",
            artist_name: "Mix Artist #{index}",
            start_at: (term + 1).days.from_now.change(hour: 20),
            event_series: series,
            event_series_assignment: "manual"
          )
          event.save!
          event.genres = [ groups.fetch(index) ]
        end
      end

      queries = capture_queries { get homepage_section_events_url(section: "stuttgart_mix") }

      assert_response :success
      group_count.times do |index|
        assert_select ".design-preview-card-title", text: "Mix Artist #{index}", count: 1
      end
      assert_select ".design-preview-card-series-pill", text: "+ 1 Termin", count: group_count
      assert_equal 2, queries.grep(/GROUP BY "events"\."event_series_id"/).size,
        "Series badge queries must stay fixed as candidate genre lanes increase"
    end
  end

  test "under 30 cards retain the active offer status when another offer is sold out" do
    @event.event_offers.create!(source: "manual", source_event_id: "performance-sold-out", sold_out: true, priority_rank: 0)

    get under_30_lane_url

    assert_response :success
    assert_select "#lane-event-grid .design-preview-card-title", text: @event.artist_name
    assert_select "#lane-event-grid .design-preview-card--sold-out", count: 0
  end

  private

  def capture_queries
    queries = []
    callback = lambda do |event|
      payload = event.payload
      queries << payload.fetch(:sql) unless payload[:cached] || payload[:name] == "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end
end
