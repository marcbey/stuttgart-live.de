require "test_helper"

class Public::EventCardGenreQueriesTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    @events = 3.times.map do |index|
      Event.create!(
        source_fingerprint: "test::card-genres::#{index}",
        artist_name: "Genre Query Artist #{index}",
        title: "Genre Query Programme #{index}",
        start_at: (index + 1).days.from_now.change(hour: 20),
        venue_record: venues(:lka_longhorn),
        city: "Stuttgart",
        status: "published",
        published_at: 1.day.ago,
        highlighted: true,
        genres: [ genres(:rock), genres(:pop) ]
      )
    end
  end

  teardown { travel_back }

  test "homepage cards load genres in a batch" do
    assert_batched_genres events_path
  end

  test "highlight lane cards load genres in a batch" do
    assert_batched_genres highlights_lane_path
  end

  test "genre lane cards preserve every genre when filtered" do
    assert_batched_genres genre_lane_path(genres(:rock).slug) do
      loaded_events = controller.view_assigns.fetch("lane_events")
      @events.each do |event|
        loaded_event = loaded_events.find { |candidate| candidate.id == event.id }
        assert_equal genres(:pop), loaded_event.primary_genre
      end
    end
  end

  test "paginated homepage cards load genres in a batch" do
    assert_batched_genres homepage_lane_events_path(lane: "highlights", mode: "design_cards")
  end

  test "related cards load candidate genres once after merging overlapping pools" do
    @events.first(2).each { |event| event.sub_genres = [ sub_genres(:rock) ] }
    @events.last.sub_genres = [ sub_genres(:jazz) ]
    queries = []
    callback = lambda do |event|
      next if event.payload[:name] == "SCHEMA" || event.payload[:cached]

      queries << event.payload[:sql].to_s
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get related_event_path(@events.first.slug), as: :turbo_stream
    end

    assert_response :success
    @events.drop(1).each { |event| assert_includes response.body, event.artist_name }
    assert_equal 2, queries.grep(/FROM "event_genres"/).size,
      "expected one genre preload for the current event and one for all related candidates"
  end

  private

  def assert_batched_genres(path)
    queries = []
    callback = lambda do |event|
      next if event.payload[:name] == "SCHEMA" || event.payload[:cached]

      queries << event.payload[:sql].to_s
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get path
      yield if block_given?
    end

    assert_response :success
    @events.each { |event| assert_includes response.body, event.artist_name }
    assert_empty queries.grep(/FROM "genres".*"event_genres"\."event_id" =/m)
  end
end
