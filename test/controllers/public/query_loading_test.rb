require "test_helper"

class Public::QueryLoadingTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    @events = 3.times.map do |index|
      series = EventSeries.create!(origin: "manual", name: "Query Loading Series #{index}")
      terms = 2.times.map do |term|
        Event.create!(
          source_fingerprint: "test::query-loading::#{index}::#{term}",
          artist_name: "Query Loading Artist #{index}",
          title: "Query Loading Programme #{index}",
          start_at: term.days.from_now.change(hour: 20),
          venue_record: venues(:lka_longhorn),
          city: "Stuttgart",
          status: "published",
          published_at: 1.day.ago,
          highlighted: true,
          event_series: series,
          event_series_assignment: "manual",
          genres: [ genres(:rock) ]
        )
      end
      image = terms.first.event_images.build(purpose: EventImage::PURPOSE_DETAIL_HERO)
      image.file.attach(create_uploaded_blob(filename: "query-loading-#{index}.png"))
      image.save!
      image.processed_optimized_variant
      EventImage::PUBLIC_VARIANT_MAX_DIMENSIONS.each_key { |size| image.processed_optimized_public_variant(size) }
      EventImage::PRESS_VARIANT_MAX_DIMENSIONS.each_key { |size| image.processed_press_variant(size) }
      terms.first
    end
  end

  teardown { travel_back }

  test "event detail batches image variants and related series counts" do
    assert_batched_render event_path(@events.first.slug)
  end

  test "detail batches ready venue and presenter logo outputs as presenters increase" do
    event = @events.first
    event.update!(organizer_notes: "Hinweise", show_organizer_notes: true)
    venue = event.venue_record
    venue.logo.attach(create_uploaded_blob(filename: "venue-logo.png", width: 640, height: 640))
    expected_outputs = [ venue.detail_logo_variant.image.blob ]
    batch_counts = [ 2, 4 ].map do |count|
      ((count - 2)...count).each do |index|
        presenter = Presenter.new(name: "Batched Presenter #{index}")
        presenter.logo.attach(create_uploaded_blob(filename: "presenter-#{index}.png", width: 640, height: 640))
        presenter.save!
        event.event_presenters.create!(presenter:, position: index + 1)
        expected_outputs << presenter.detail_logo_variant.image.blob
      end
      queries = []
      callback = lambda do |notification|
        sql = notification.payload[:sql]
        queries << sql if sql.match?(/FROM "active_storage_(?:attachments|blobs|variant_records)"/)
      end
      assert_no_difference "ActiveStorage::VariantRecord.count" do
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get event_path(event.slug) }
      end
      assert_response :success
      expected_outputs.each { |blob| assert_select "img[src=?]", rails_storage_proxy_path(blob, only_path: true), minimum: 1 }
      assert_empty queries.grep(/FROM "active_storage_variant_records".*"variation_digest" =/m)
      queries.group_by { |sql| sql[/FROM "(active_storage_\w+)"/, 1] }.transform_values(&:length)
    end
    assert_equal batch_counts.first, batch_counts.last, "Logo query batches must stay fixed for two versus four presenters"
  end

  test "event detail defers inherited header search until the overlay is requested" do
    queries = []
    callback = lambda do |event|
      queries << event.payload[:sql].to_s unless event.payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get event_path(@events.first.slug, q: "Query Loading Artist")
    end

    assert_response :success
    assert_select 'input[name="q"][value="Query Loading Artist"]', minimum: 1
    assert_select 'form[action="/search"][method="get"]', minimum: 1
    assert_empty queries.grep(/FROM "events".*ILIKE/m)

    get search_overlay_events_path(q: "Query Loading Artist")

    assert_response :success
    assert_select ".public-search-result-artist", text: @events.first.artist_name
  end

  test "event lane batches image variants and series counts" do
    assert_batched_render highlights_lane_path
  end

  test "all Stuttgart lane batches today series counts" do
    assert_batched_render all_stuttgart_lane_path
  end

  test "news detail batches sidebar image variants and series counts" do
    post = BlogPost.create!(
      title: "Query Loading News",
      teaser: "Aktuelle Konzertnachrichten",
      body: "<div>Neuigkeiten aus Stuttgart.</div>",
      author: users(:one),
      status: "published",
      published_at: 1.day.ago
    )

    assert_batched_render news_path(post.slug)
  end

  private

  def assert_batched_render(path)
    queries = []
    callback = lambda do |event|
      sql = event.payload[:sql].to_s
      next if event.payload[:name] == "SCHEMA" || event.payload[:cached]

      queries << sql
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get path }

    assert_response :success
    assert_select "img.design-preview-card-image", minimum: 2
    assert_select ".design-preview-card-series-pill", text: "+ 1 Termin", minimum: 2
    assert_empty queries.grep(/FROM "active_storage_variant_records".*"variation_digest" =/m)
    assert_empty queries.grep(/FROM "active_storage_attachments".*"record_id" =.*LIMIT/m)
    assert_empty queries.grep(/COUNT\(DISTINCT "events"\."id"\).*"event_series_id" =/m)
  end
end
