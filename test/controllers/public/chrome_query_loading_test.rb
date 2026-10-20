require "test_helper"

class Public::ChromeQueryLoadingTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    StaticPageDefaults.ensure!
    AppSetting.homepage_genre_lane_slugs_record.update!(value: [ genres(:rock).slug ])
    @event = events(:published_one)
    @event.update!(highlighted: true, genres: [ genres(:rock) ])
    @post = BlogPost.create!(title: @event.artist_name, teaser: "Konzertnachrichten", body: "<div>#{@event.artist_name}</div>", author: users(:one), status: "published", published_at: 1.day.ago)
  end

  teardown do
    AppSetting.reset_cache!
    travel_back
  end

  test "service navigation retains genre links without hidden event lanes or idle searches" do
    queries = capture_queries { get faq_path }

    assert_response :success
    assert_select ".design-preview-header-genres a", minimum: 1
    assert_select ".design-preview-card-title", text: @event.artist_name
    assert_empty queries.grep(/FROM "genres".*"event_genres"\."event_id" =/m)
    assert_no_hidden_queries queries
    assert_empty queries.grep(/FROM "events".*INNER JOIN "genres"/m)
    assert_select "template .public-search-result-artist", text: @event.artist_name, count: 0
  end

  test "news genre sidebar does not load fallback highlights or hidden navigation lanes" do
    queries = capture_queries { get news_path(@post.slug) }

    assert_response :success
    assert_select ".design-news-preview-highlights h2", text: genres(:rock).name
    assert_select ".design-preview-card-title", text: @event.artist_name
    assert_no_hidden_queries queries
    assert_empty queries.grep(/FROM "events".*"events"\."highlighted" =/m)
    candidates = queries.grep(/\ASELECT.*FROM "events"/m).select { |sql| sql.include?('"artist_name"') }
    assert_not_empty candidates
    candidates.each do |sql|
      refute_match(/DISTINCT|"events"\.\*|JOIN "(?:event_images|event_offers|active_storage_)/, sql)
    end
  end

  test "news pagination loads only the visible news cards" do
    queries = capture_queries { get news_index_path(offset: 10, format: :turbo_stream) }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_empty queries.grep(/FROM "events"/)
  end

  test "homepage batches attachment lookups for rendered cards" do
    queries = capture_queries { get events_path }

    assert_response :success
    assert_empty queries.grep(/FROM "active_storage_attachments".*"record_id" =.*LIMIT/m)
  end

  private

  def assert_no_hidden_queries(queries)
    assert_empty queries.grep(/FROM "events".*"events"\."promotion_banner" =/m)
  end

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
