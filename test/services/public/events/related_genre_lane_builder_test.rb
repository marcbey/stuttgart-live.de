require "test_helper"

class Public::Events::RelatedGenreLaneBuilderTest < ActiveSupport::TestCase
  setup do
    EventGenre.delete_all
    EventSubGenre.delete_all
    AppSetting.where(key: AppSetting::SKS_PROMOTER_IDS_KEY).delete_all
    AppSetting.create!(key: AppSetting::SKS_PROMOTER_IDS_KEY, value: [ "10135", "Russ Klassik" ])
    AppSetting.reset_cache!

    @rock_group = genres(:rock)
    @pop_group = genres(:pop)
    @metal_group = genres(:metal)
  end

  teardown do
    AppSetting.reset_cache!
  end

  test "ranks exact sub genre matches before partial sub genre and genre matches" do
    current_event = build_lane_event(slug: "related-rank-current", artist_name: "Current Event", start_at: 4.days.from_now.change(hour: 20))
    exact_sub_genres = build_lane_event(slug: "related-rank-exact-sub", artist_name: "Exact Sub Genres", start_at: 10.days.from_now.change(hour: 20))
    partial_two_sub_genres = build_lane_event(slug: "related-rank-partial-two-sub", artist_name: "Partial Two Sub Genres", start_at: 5.days.from_now.change(hour: 20))
    partial_one_sub_genre = build_lane_event(slug: "related-rank-partial-one-sub", artist_name: "Partial One Sub Genre", start_at: 4.days.from_now.change(hour: 21))
    exact_two_genres = build_lane_event(slug: "related-rank-exact-genres", artist_name: "Exact Two Genres", start_at: 3.days.from_now.change(hour: 20))
    one_genre = build_lane_event(slug: "related-rank-one-genre", artist_name: "One Genre", start_at: 2.days.from_now.change(hour: 20))

    build_lane_enrichment(event: current_event, genres: [ "Rock", "Pop" ], sub_genres: [ "Rock", "Indie", "Pop" ])
    build_lane_enrichment(event: exact_sub_genres, genres: [ "Metal" ], sub_genres: [ "Pop", "Rock", "Indie" ])
    build_lane_enrichment(event: partial_two_sub_genres, genres: [ "Metal" ], sub_genres: [ "Rock", "Indie" ])
    build_lane_enrichment(event: partial_one_sub_genre, genres: [ "Metal" ], sub_genres: [ "Indie" ])
    build_lane_enrichment(event: exact_two_genres, genres: [ "Pop", "Rock" ], sub_genres: [ "Jazz" ])
    build_lane_enrichment(event: one_genre, genres: [ "Rock" ], sub_genres: [ "Jazz" ])

    lane = build_builder(event: current_event).call

    assert_equal @pop_group.id, lane.group.id
    assert_equal [
      exact_sub_genres.id,
      partial_two_sub_genres.id,
      partial_one_sub_genre.id,
      exact_two_genres.id,
      one_genre.id
    ], lane.events.map(&:id)
  end

  test "sorts partial sub genre matches by overlap count before highlight priority" do
    current_event = build_lane_event(slug: "related-overlap-current", artist_name: "Current Event", start_at: 4.days.from_now.change(hour: 20))
    one_highlighted = build_lane_event(slug: "related-overlap-one-highlighted", artist_name: "One Highlighted", start_at: 5.days.from_now.change(hour: 18), highlighted: true)
    two_regular = build_lane_event(slug: "related-overlap-two-regular", artist_name: "Two Regular", start_at: 5.days.from_now.change(hour: 19))
    two_sks = build_lane_event(slug: "related-overlap-two-sks", artist_name: "Two SKS", start_at: 5.days.from_now.change(hour: 22), promoter_id: "10135")

    build_lane_enrichment(event: current_event, genres: [ "Rock" ], sub_genres: [ "Rock", "Indie", "Pop" ])
    build_lane_enrichment(event: one_highlighted, genres: [ "Metal" ], sub_genres: [ "Rock" ])
    build_lane_enrichment(event: two_regular, genres: [ "Metal" ], sub_genres: [ "Rock", "Indie" ])
    build_lane_enrichment(event: two_sks, genres: [ "Metal" ], sub_genres: [ "Indie", "Pop" ])

    lane = build_builder(event: current_event).call

    assert_equal [
      two_sks.id,
      two_regular.id,
      one_highlighted.id
    ], lane.events.map(&:id)
  end

  test "sorts equal relevance matches by sks and highlighted priority before chronology" do
    current_event = build_lane_event(slug: "related-priority-current", artist_name: "Current Event", start_at: 4.days.from_now.change(hour: 20))
    normal_earlier = build_lane_event(slug: "related-priority-normal-earlier", artist_name: "Normal Earlier", start_at: 5.days.from_now.change(hour: 18))
    highlighted_later = build_lane_event(slug: "related-priority-highlighted", artist_name: "Highlighted Later", start_at: 5.days.from_now.change(hour: 22), highlighted: true)
    sks_middle = build_lane_event(slug: "related-priority-sks", artist_name: "SKS Middle", start_at: 5.days.from_now.change(hour: 20), promoter_name: "Russ Klassik")
    normal_latest = build_lane_event(slug: "related-priority-normal-latest", artist_name: "Normal Latest", start_at: 5.days.from_now.change(hour: 23))

    [ current_event, normal_earlier, highlighted_later, sks_middle, normal_latest ].each do |event|
      build_lane_enrichment(event: event, genres: [ "Rock" ], sub_genres: [ "Rock" ])
    end

    lane = build_builder(event: current_event).call

    assert_equal [
      sks_middle.id,
      highlighted_later.id,
      normal_earlier.id,
      normal_latest.id
    ], lane.events.map(&:id)
  end

  test "excludes the current event series and deduplicates other series by best ranked event" do
    current_series = EventSeries.create!(origin: "manual", name: "Current Series")
    other_series = EventSeries.create!(origin: "manual", name: "Other Series")
    current_event = build_lane_event(slug: "related-series-current", artist_name: "Current Event", start_at: 4.days.from_now.change(hour: 20))
    same_series_event = build_lane_event(slug: "related-series-same", artist_name: "Same Series", start_at: 5.days.from_now.change(hour: 18))
    other_series_best = build_lane_event(slug: "related-series-best", artist_name: "Other Series Best", start_at: 7.days.from_now.change(hour: 20))
    other_series_weaker = build_lane_event(slug: "related-series-weaker", artist_name: "Other Series Weaker", start_at: 5.days.from_now.change(hour: 20))

    current_event.update!(event_series: current_series, event_series_assignment: "manual")
    same_series_event.update!(event_series: current_series, event_series_assignment: "manual")
    other_series_best.update!(event_series: other_series, event_series_assignment: "manual")
    other_series_weaker.update!(event_series: other_series, event_series_assignment: "manual")

    build_lane_enrichment(event: current_event, genres: [ "Rock" ], sub_genres: [ "Rock", "Indie" ])
    build_lane_enrichment(event: same_series_event, genres: [ "Rock" ], sub_genres: [ "Rock", "Indie" ])
    build_lane_enrichment(event: other_series_best, genres: [ "Metal" ], sub_genres: [ "Rock", "Indie" ])
    build_lane_enrichment(event: other_series_weaker, genres: [ "Metal" ], sub_genres: [ "Rock" ])

    lane = build_builder(event: current_event).call

    assert_equal [ other_series_best.id ], lane.events.map(&:id)
    assert_equal [ other_series.id ], lane.effective_series_ids
  end

  test "ignores unpublished and past matching events" do
    current_event = build_lane_event(slug: "related-filter-current", artist_name: "Current Event", start_at: 4.days.from_now.change(hour: 20))
    published_future = build_lane_event(slug: "related-filter-published", artist_name: "Published Future", start_at: 5.days.from_now.change(hour: 20))
    unpublished_future = build_lane_event(slug: "related-filter-unpublished", artist_name: "Unpublished Future", start_at: 5.days.from_now.change(hour: 21), status: "needs_review", published_at: nil)
    past_published = build_lane_event(slug: "related-filter-past", artist_name: "Past Published", start_at: 2.days.ago.change(hour: 20), published_at: 5.days.ago)

    [ current_event, published_future, unpublished_future, past_published ].each do |event|
      build_lane_enrichment(event: event, genres: [ "Rock" ], sub_genres: [ "Rock" ])
    end

    lane = build_builder(event: current_event).call

    assert_equal [ published_future.id ], lane.events.map(&:id)
  end

  test "uses 20 as the default limit for related lane events" do
    current_event = build_lane_event(slug: "related-limit-current", artist_name: "Current Event", start_at: 2.days.from_now.change(hour: 20))
    build_lane_enrichment(event: current_event, genres: [ "Rock" ], sub_genres: [ "Rock" ])

    related_events = 25.times.map do |index|
      event = build_lane_event(
        slug: "related-limit-#{index}",
        artist_name: "Related Limit #{index}",
        start_at: (index + 3).days.from_now.change(hour: 20)
      )
      build_lane_enrichment(event: event, genres: [ "Rock" ], sub_genres: [ "Rock" ])
      event
    end

    lane = build_builder(event: current_event).call

    assert_equal 20, lane.events.size
    assert_equal related_events.first(20).map(&:id), lane.events.map(&:id)
    assert_not_includes lane.events.map(&:id), current_event.id
  end

  test "returns nil when no related event matches sub genres or genres" do
    current_event = build_lane_event(slug: "related-only-current", artist_name: "Current Event", start_at: 4.days.from_now.change(hour: 20))
    unrelated_event = build_lane_event(slug: "related-unrelated", artist_name: "Unrelated Event", start_at: 5.days.from_now.change(hour: 20))

    build_lane_enrichment(event: current_event, genres: [ "Rock" ], sub_genres: [ "Rock" ])
    build_lane_enrichment(event: unrelated_event, genres: [ "Pop" ], sub_genres: [ "Pop" ])

    assert_nil build_builder(event: current_event).call
  end

  private

  def build_builder(event:)
    Public::Events::RelatedGenreLaneBuilder.new(
      event: event,
      relation: Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day)
    )
  end

  def build_lane_event(slug:, artist_name:, start_at:, highlighted: false, promoter_id: nil, promoter_name: nil, status: "published", published_at: 1.day.ago)
    Event.create!(
      slug: slug,
      source_fingerprint: "test::service::related-genre-lane::#{slug}",
      title: "#{artist_name} Title",
      artist_name: artist_name,
      start_at: start_at,
      venue: "Club Zentral",
      city: "Stuttgart",
      promoter_id: promoter_id,
      promoter_name: promoter_name,
      highlighted: highlighted,
      status: status,
      published_at: published_at,
      source_snapshot: {}
    )
  end

  def build_lane_enrichment(event:, genres:, sub_genres:)
    event.genres = genres.map { |name| genre_for(name) }
    event.sub_genres = sub_genres.map { |name| sub_genre_for(name) }
  end

  def genre_for(name)
    case name
    when "Rock"
      @rock_group
    when "Pop"
      @pop_group
    when "Metal"
      @metal_group
    else
      Genre.find_by!(name: name)
    end
  end

  def sub_genre_for(name)
    SubGenre.find_by!(name: name)
  end
end
