require "test_helper"

class Public::CanceledHomepageHighlightsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    Event.update_all(status: "needs_review")
    @canceled = create_highlight("Canceled", canceled: true)
    @available = create_highlight("Available")
  end

  teardown { travel_back }

  test "canceled events are absent from homepage highlights but remain in the overview and detail" do
    get events_url

    assert_response :success
    assert_select ".design-preview-highlights a[href='#{event_path(@canceled.slug)}']", count: 0
    assert_select ".design-preview-feature-track a[href='#{event_path(@available.slug)}']", count: 1
    assert_select ".design-preview-mobile-highlight-row a[href='#{event_path(@available.slug)}']", minimum: 1

    get all_stuttgart_lane_path

    assert_response :success
    assert_select "a[href='#{event_path(@canceled.slug)}']", minimum: 1
    assert_includes response.body, "Abgesagt"

    get event_path(@canceled.slug)

    assert_response :success
    assert_includes response.body, "Abgesagt"
  end

  test "highlight pagination skips canceled events before applying the page limit" do
    @canceled.update!(start_at: 1.day.from_now)
    controller = Public::EventsController.new
    controller.params = ActionController::Parameters.new(filter: "all")
    controller.send(:set_browse_state)

    page = controller.send(:homepage_lane_page, "highlights", per_page: 1)

    assert_equal [ @available.id ], page.events.map(&:id)
    assert_nil page.next_cursor

    get homepage_lane_events_url(lane: "highlights", mode: "rows")

    assert_response :success
    assert_not_includes response.body, @canceled.artist_name
    assert_includes response.body, @available.artist_name
  end

  test "highlight fallback also excludes canceled events" do
    Event.update_all(highlighted: false, promoter_id: nil, promoter_name: nil, promotion_banner: false)

    get events_url

    assert_response :success
    assert_select ".design-preview-highlights a[href='#{event_path(@canceled.slug)}']", count: 0
    assert_select ".design-preview-highlights a[href='#{event_path(@available.slug)}']", minimum: 1
  end

  test "sold out events and manual overrides of imported cancellations remain highlights" do
    @available.event_offers.first.update!(sold_out: true)
    @canceled.event_offers.create!(source: "manual", source_event_id: "manual-override", ticket_url: "https://tickets.example.test/manual", priority_rank: 0)

    get events_url

    assert_response :success
    [ @available, @canceled ].each do |event|
      assert_select ".design-preview-feature-track a[href='#{event_path(event.slug)}']", count: 1
      assert_select ".design-preview-mobile-highlight-row a[href='#{event_path(event.slug)}']", minimum: 1
    end
  end

  test "canceled event videos are excluded from the highlight playlist" do
    [ @canceled, @available ].each do |event|
      event.highlight_video_file.attach(io: StringIO.new("video"), filename: "highlight.mp4", content_type: "video/mp4")
    end

    get events_url

    assert_response :success
    playlists = Nokogiri::HTML.parse(response.body).css("[data-video-sound-playlist-value]").flat_map do |node|
      JSON.parse(node["data-video-sound-playlist-value"])
    end
    assert_includes playlists.map { |clip| clip.fetch("title") }, @available.artist_name
    assert_not_includes playlists.map { |clip| clip.fetch("title") }, @canceled.artist_name
  end

  test "the default portrait trailer does not promote its canceled event" do
    @canceled.update!(slug: "lea-2027-04-25")

    get events_url

    assert_response :success
    assert_select ".design-preview-highlights a[href='#{event_path(@canceled.slug)}']", count: 0
  end

  private

  def create_highlight(name, canceled: false)
    event = Event.create!(
      artist_name: "#{name} Highlight Artist", title: "Tour", start_at: 2.days.from_now,
      venue_record: venues(:lka_longhorn), city: "Stuttgart", status: "published",
      published_at: 1.day.ago, highlighted: true, promotion_banner: true
    )
    event.promotion_banner_image.attach(create_uploaded_blob(filename: "#{name.downcase}-banner.png"))
    event.event_offers.create!(
      source: "eventim", source_event_id: "#{name.downcase}-offer", priority_rank: 0,
      ticket_url: "https://tickets.example.test/#{name.downcase}",
      metadata: { "availability_status" => canceled ? "canceled" : "available" }
    )
    event
  end
end
