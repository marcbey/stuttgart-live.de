require "test_helper"

class PublicEventFragmentsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    @event = events(:published_one)
    @event.update!(min_price: 20, highlighted: true)
    @previous_cache = Rails.cache
    @previous_controller_cache = Public::EventsController.cache_store
    @previous_caching = Public::EventsController.perform_caching
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Public::EventsController.cache_store = Rails.cache
    Public::EventsController.perform_caching = true
    AppSetting.reset_cache!
  end

  teardown do
    Rails.cache = @previous_cache
    Public::EventsController.cache_store = @previous_controller_cache
    Public::EventsController.perform_caching = @previous_caching
    AppSetting.reset_cache!
    travel_back
  end

  test "anonymous modern event grids reuse rendered cards on identical requests" do
    assert_operator rendered_cards { get highlights_lane_url }, :>, 0
    assert_equal 0, rendered_cards { get highlights_lane_url }
    assert_select "#lane-event-grid .design-preview-card-title", text: @event.artist_name
  end

  test "warm cards refresh event offer and genre changes" do
    get under_30_lane_url
    travel 1.second do
      @event.update!(artist_name: "Frischer Künstler")
      @event.event_offers.first.update!(metadata: { availability_status: "canceled" })
      genres(:rock).update_columns(name: "Frisches Genre", updated_at: Time.current)
    end

    get under_30_lane_url

    assert_select "#lane-event-grid .design-preview-card-title", text: "Frischer Künstler"
    assert_select "#lane-event-grid .design-preview-card-status-pill", text: "Abgesagt"
    assert_select "#lane-event-grid .design-preview-card-genre", text: "Frisches Genre"
  end

  test "authenticated requests bypass anonymous fragments and retain editorial controls" do
    get highlights_lane_url
    sign_in_as users(:one)

    assert_operator rendered_cards { get highlights_lane_url }, :>, 0
    assert_select "#lane-event-grid .event-card-admin-link", minimum: 1

    sign_out
    get highlights_lane_url
    assert_select "#lane-event-grid .event-card-admin-link", count: 0
  end

  test "warm fragments do not retain unpublished or newly published events" do
    get highlights_lane_url
    @event.update!(status: "ready_for_publish", published_at: nil)
    get highlights_lane_url
    assert_select "#lane-event-grid .design-preview-card-title", text: @event.artist_name, count: 0

    @event.update!(status: "published", published_at: Time.current)
    get highlights_lane_url
    assert_select "#lane-event-grid .design-preview-card-title", text: @event.artist_name
  end

  test "homepage highlight groups reuse cards without editorial controls" do
    first = rendered_cards { get root_url }
    assert_operator first, :>, 1
    assert_operator rendered_cards { get root_url }, :<, first
    assert_select ".home-featured-section .event-card-admin-link", count: 0
  end

  test "warm media reflects changed image text and file replacement" do
    image = @event.event_images.build(purpose: EventImage::PURPOSE_SLIDER, alt_text: "Altes Bild")
    image.file.attach(create_uploaded_blob)
    image.save!
    get highlights_lane_url
    assert_select "#lane-event-grid img[alt='Altes Bild']"
    old_source = css_select("#lane-event-grid img").first["src"]

    travel 1.second do
      image.update!(alt_text: "Frisches Bild")
      image.file.attach(create_uploaded_blob(filename: "replacement.png"))
    end
    get highlights_lane_url
    assert_select "#lane-event-grid img[alt='Frisches Bild']"
    assert_not_equal old_source, css_select("#lane-event-grid img").first["src"]
  end

  test "a venue mapping change updates already warm cards" do
    get highlights_lane_url
    AppSetting.create!(key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY, value: [ { "alias" => @event.venue_record.name, "canonical" => venues(:im_wizemann).name } ])
    AppSetting.reset_cache!

    get highlights_lane_url

    assert_select "#lane-event-grid .design-preview-card-location", text: venues(:im_wizemann).name
  end

  test "scheduled publication becomes visible while a grid is warm" do
    scheduled = @event.dup
    scheduled.assign_attributes(slug: "scheduled-fragment", source_fingerprint: "test::fragment::scheduled", artist_name: "Geplanter Künstler", status: "ready_for_publish", published_at: 1.minute.from_now)
    scheduled.save!
    scheduled.update_columns(status: "published")
    get highlights_lane_url
    assert_select "#lane-event-grid .design-preview-card-title", text: scheduled.artist_name, count: 0

    travel 2.minutes do
      get highlights_lane_url
      assert_select "#lane-event-grid .design-preview-card-title", text: scheduled.artist_name
    end
  end

  test "warm cards refresh series counts when another term is published" do
    series = EventSeries.create!(origin: "manual", name: "Cache-Reihe")
    @event.update!(event_series: series, event_series_assignment: "manual")
    2.times do |index|
      term = @event.dup
      term.assign_attributes(slug: "fragment-term-#{index}", source_fingerprint: "test::fragment::term::#{index}", start_at: @event.start_at + (index + 1).days, status: index.zero? ? "published" : "needs_review")
      term.save!
    end
    get highlights_lane_url
    assert_select "#lane-event-grid .design-preview-card-series-pill", text: "+ 1 Termin"

    Event.find_by!(slug: "fragment-term-1").update!(status: "published")
    get highlights_lane_url
    assert_select "#lane-event-grid .design-preview-card-series-pill", text: "+ 2 Termine"
  end

  test "warm cards refresh their chosen offer when provider priorities change" do
    @event.event_offers.create!(source: "eventim", source_event_id: "fragment-priority", sold_out: true, priority_rank: 10)
    get highlights_lane_url
    assert_select "#lane-event-grid .design-preview-card-status-pill", text: "Ausverkauft", count: 0

    provider_priorities(:easyticket).update!(priority_rank: 30)
    get highlights_lane_url
    assert_select "#lane-event-grid .design-preview-card-status-pill", text: "Ausverkauft"
  end

  private

  def rendered_cards
    count = 0
    callback = ->(notification) { count += 1 if notification.payload[:identifier].to_s.end_with?("/_design_preview_card.html.erb") }
    ActiveSupport::Notifications.subscribed(callback, "render_partial.action_view") { yield }
    assert_response :success
    count
  end
end
