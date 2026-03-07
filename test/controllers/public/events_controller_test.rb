require "test_helper"

class Public::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @published_event = events(:published_one)
    @past_published_event = events(:published_past_one)
    @user = users(:one)
  end

  test "index is publicly accessible" do
    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, "Published Artist"
    assert_not_includes response.body, "Past Artist"
    assert_not_includes response.body, "Review Artist"
    assert_not_includes response.body, "event-card-status-select"
  end

  test "index defaults to SKS filter" do
    future_start = 10.days.from_now.change(hour: 20, min: 0, sec: 0)

    sks_event = Event.create!(
      slug: "default-sks-event",
      source_fingerprint: "test::default::sks",
      title: "Default SKS Event",
      artist_name: "Default SKS Artist",
      start_at: future_start,
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "382",
      source_snapshot: {}
    )

    non_sks_event = Event.create!(
      slug: "default-non-sks-event",
      source_fingerprint: "test::default::non-sks",
      title: "Default Non SKS Event",
      artist_name: "Default Non SKS Artist",
      start_at: future_start + 1.hour,
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "99999",
      source_snapshot: {}
    )

    get events_url

    assert_response :success
    assert_includes response.body, sks_event.artist_name
    assert_not_includes response.body, non_sks_event.artist_name
  end

  test "index can be filtered to SKS events" do
    future_start = 10.days.from_now.change(hour: 20, min: 0, sec: 0)

    sks_easy_event = Event.create!(
      slug: "sks-easy-event",
      source_fingerprint: "test::sks::easy",
      title: "SKS Easy Event",
      artist_name: "SKS Easy Artist",
      start_at: future_start,
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "382",
      source_snapshot: {}
    )

    sks_eventim_event = Event.create!(
      slug: "sks-eventim-event",
      source_fingerprint: "test::sks::eventim",
      title: "SKS Eventim Event",
      artist_name: "SKS Eventim Artist",
      start_at: future_start + 1.hour,
      venue: "Porsche-Arena",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "10135",
      source_snapshot: {}
    )

    sks_easyticket_promoter_event = Event.create!(
      slug: "sks-easyticket-promoter-event",
      source_fingerprint: "test::sks::easyticket::promoter",
      title: "SKS Easyticket Promoter Event",
      artist_name: "SKS Easyticket Promoter Artist",
      start_at: future_start + 90.minutes,
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "382",
      source_snapshot: {}
    )

    non_sks_event = Event.create!(
      slug: "non-sks-event",
      source_fingerprint: "test::non::sks",
      title: "Non SKS Event",
      artist_name: "Other Artist",
      start_at: future_start + 2.hours,
      venue: "Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "99999",
      source_snapshot: {}
    )

    get events_url(filter: "sks")

    assert_response :success
    assert_includes response.body, sks_easy_event.artist_name
    assert_includes response.body, sks_eventim_event.artist_name
    assert_includes response.body, sks_easyticket_promoter_event.artist_name
    assert_not_includes response.body, non_sks_event.artist_name
    assert_includes response.body, "filter=sks"
  end

  test "index can be filtered to a specific day" do
    selected_date = 12.days.from_now.to_date
    selected_start = selected_date.to_time.in_time_zone.change(hour: 20, min: 0, sec: 0)

    matching_event = Event.create!(
      slug: "day-filter-match",
      source_fingerprint: "test::day::match",
      title: "Day Filter Match",
      artist_name: "Day Match Artist",
      start_at: selected_start,
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "10135",
      source_snapshot: {}
    )

    other_day_event = Event.create!(
      slug: "day-filter-other",
      source_fingerprint: "test::day::other",
      title: "Day Filter Other",
      artist_name: "Other Day Artist",
      start_at: selected_start + 1.day,
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      promoter_id: "10135",
      source_snapshot: {}
    )

    get events_url(filter: "sks", event_date: selected_date.iso8601)

    assert_response :success
    assert_includes response.body, matching_event.artist_name
    assert_not_includes response.body, other_day_event.artist_name
    assert_includes response.body, "event_date=#{selected_date.iso8601}"
  end

  test "show renders published event by slug" do
    get event_url(@published_event.slug)

    assert_response :success
    assert_includes response.body, "Published Artist"
    assert_match(/Beginn:\s*\d{2}:\d{2}\s*Uhr/, response.body)
    assert_match(/Einlass:\s*\d{2}:\d{2}\s*Uhr/, response.body)
    assert_includes response.body, "Preis: 45 EUR"
  end

  test "show renders einlass when present" do
    event = Event.create!(
      slug: "published-event-with-einlass",
      source_fingerprint: "test::public::published::einlass",
      title: "Published Event With Einlass",
      artist_name: "Published Artist With Einlass",
      start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0),
      doors_at: 10.days.from_now.change(hour: 18, min: 30, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_match(/Einlass:\s*\d{2}:\d{2}\s*Uhr/, response.body)
  end

  test "show renders redaktionsnotiz section when editor notes are present" do
    event = Event.create!(
      slug: "published-event-with-editor-notes",
      source_fingerprint: "test::public::published::editor-notes",
      title: "Published Event With Editor Notes",
      artist_name: "Published Artist With Notes",
      start_at: 11.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      event_info: "Öffentliche Beschreibung",
      editor_notes: "Interner Hinweis\nZweite Zeile",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )

    get event_url(event.slug)

    assert_response :success
    assert_includes response.body, "Redaktionsnotiz"
    assert_includes response.body, "Interner Hinweis"
  end

  test "show includes backend badge for authenticated users" do
    sign_in_as(@user)

    get event_url(@published_event.slug)

    assert_response :success
    expected_link = backend_events_path(status: @published_event.status, event_id: @published_event.id).gsub("&", "&amp;")
    assert_includes response.body, expected_link
  end

  test "show returns not found for unpublished events" do
    get event_url(events(:needs_review_one).slug)

    assert_response :not_found
  end

  test "show renders unpublished events for authenticated users with status badge" do
    sign_in_as(@user)

    event = events(:needs_review_one)
    get event_url(event.slug)

    assert_response :success
    assert_includes response.body, "Review"
  end

  test "show renders rejected events for authenticated users with abgelehnt badge" do
    sign_in_as(@user)

    rejected_event = Event.create!(
      slug: "rejected-public-detail",
      source_fingerprint: "test::public::rejected::detail",
      title: "Rejected Public Detail",
      artist_name: "Rejected Artist",
      start_at: 8.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "rejected",
      source_snapshot: {}
    )

    get event_url(rejected_event.slug)

    assert_response :success
    assert_includes response.body, "Abgelehnt"
  end

  test "show renders published past events by slug" do
    get event_url(@past_published_event.slug)

    assert_response :success
    assert_includes response.body, "Past Artist"
  end

  test "show renders past events for authenticated users with vergangen badge" do
    sign_in_as(@user)

    get event_url(@past_published_event.slug)

    assert_response :success
    assert_includes response.body, "Vergangen"
  end

  test "index shows status overlay for authenticated users" do
    sign_in_as(@user)

    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, "event-card-status-select"
    assert_includes response.body, status_event_path(@published_event.slug)
    assert_includes response.body, "data-controller=\"public-card-status\""
    assert_includes response.body, "change-&gt;public-card-status#change"
    assert_includes response.body, "/backend/events?event_id=#{@published_event.id}&amp;status=#{@published_event.status}"
  end

  test "status update requires authentication" do
    patch status_event_url(@published_event.slug), params: { status: "needs_review" }

    assert_redirected_to new_session_url
  end

  test "authenticated user can update event status from public cards" do
    sign_in_as(@user)

    patch status_event_url(@published_event.slug), params: { status: "needs_review", page: "1", filter: "all", event_date: "2026-06-01" }

    assert_redirected_to events_url(page: "1", filter: "all", event_date: "2026-06-01")
    assert_equal "needs_review", @published_event.reload.status
    assert_nil @published_event.published_at
    assert_nil @published_event.published_by_id
  end

  test "turbo status update removes event card when event becomes unpublished" do
    sign_in_as(@user)

    patch status_event_url(@published_event.slug),
      params: { status: "needs_review", card_slot: "grid_default" },
      as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "action=\"remove\""
    assert_includes response.body, "target=\"card_event_#{@published_event.id}\""
  end

  test "show prefers editorial hero and renders slider images with sub text" do
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      alt_text: "Hero Alt"
    )
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_GRID_TILE,
      grid_variant: EventImage::GRID_VARIANT_1X1,
      alt_text: "Grid Alt"
    )
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_SLIDER,
      alt_text: "Slider Alt",
      sub_text: "Slider Subline"
    )

    get event_url(@published_event.slug)

    assert_response :success
    assert_includes response.body, "Hero Alt"
    assert_includes response.body, "Slider Subline"
    assert_includes response.body, "rails/active_storage"
  end

  test "show falls back to editorial grid image when no detail hero exists" do
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_GRID_TILE,
      grid_variant: EventImage::GRID_VARIANT_2X1,
      alt_text: "Grid Hero Fallback Alt"
    )

    get event_url(@published_event.slug)

    assert_response :success
    assert_includes response.body, "Grid Hero Fallback Alt"
    assert_includes response.body, "rails/active_storage"
  end

  test "index uses editorial image for grid variant slot" do
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_GRID_TILE,
      grid_variant: EventImage::GRID_VARIANT_2X2,
      alt_text: "Grid 2x2 Alt"
    )
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_GRID_TILE,
      grid_variant: EventImage::GRID_VARIANT_1X1,
      alt_text: "Grid 1x1 Alt"
    )

    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, "event-card-grid-2-2"
    assert_includes response.body, "Grid 2x2 Alt"
    assert_includes response.body, "rails/active_storage"
  end

  test "index uses the only available editorial grid variant even outside the default pattern slot" do
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_GRID_TILE,
      grid_variant: EventImage::GRID_VARIANT_1X2,
      alt_text: "Grid 1x2 Alt"
    )

    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, "event-card-grid-1-2"
    assert_includes response.body, "Grid 1x2 Alt"
  end

  test "index prefers a single non-default editorial grid variant over 1x1" do
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_GRID_TILE,
      grid_variant: EventImage::GRID_VARIANT_1X1,
      alt_text: "Grid 1x1 Alt"
    )
    create_event_image(
      event: @published_event,
      purpose: EventImage::PURPOSE_GRID_TILE,
      grid_variant: EventImage::GRID_VARIANT_1X2,
      alt_text: "Grid 1x2 Preferred Alt"
    )

    get events_url(filter: "all")

    assert_response :success
    assert_includes response.body, "event-card-grid-1-2"
    assert_includes response.body, "Grid 1x2 Preferred Alt"
  end

  private

  def create_event_image(event:, purpose:, grid_variant: nil, alt_text: nil, sub_text: nil)
    image = event.event_images.new(
      purpose: purpose,
      grid_variant: grid_variant,
      alt_text: alt_text,
      sub_text: sub_text
    )
    binary = File.binread(Rails.root.join("test/fixtures/files/test_image.png"))
    image.file.attach(
      io: StringIO.new(binary),
      filename: "test_image.png",
      content_type: "image/png"
    )
    image.save!
    image
  end
end
