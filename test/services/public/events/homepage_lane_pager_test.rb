require "test_helper"

class Public::Events::HomepageLanePagerTest < ActiveSupport::TestCase
  setup do
    @context = { lane: "genre", slug: "rock-alternative" }
    @source_prefix = "test::service::homepage-lane-pager::#{SecureRandom.hex(4)}"
  end

  test "pages through all events without offset" do
    events = 25.times.map do |index|
      build_event(index: index)
    end

    first = pager.call
    second = pager(cursor: first.next_cursor).call
    third = pager(cursor: second.next_cursor).call

    assert_equal events.first(10).map(&:id), first.events.map(&:id)
    assert_equal events.slice(10, 10).map(&:id), second.events.map(&:id)
    assert_equal events.last(5).map(&:id), third.events.map(&:id)
    assert_nil third.next_cursor
  end

  test "deduplicates event series across pages" do
    series = EventSeries.create!(origin: "manual", name: "Reihe")
    first = build_event(index: 0, event_series: series)
    duplicate = build_event(index: 20, event_series: series)
    other_events = 11.times.map { |index| build_event(index: index + 1) }

    page = pager.call
    next_page = pager(cursor: page.next_cursor).call

    assert_includes page.events.map(&:id), first.id
    assert_not_includes next_page.events.map(&:id), duplicate.id
    assert_equal other_events.last.id, next_page.events.last.id
  end

  test "rejects cursors from another lane context" do
    11.times { |index| build_event(index: index) }
    first = pager.call

    assert_raises Public::Events::HomepageLanePager::InvalidCursor do
      pager(context: { lane: "genre", slug: "pop-indie-singer-songwriter" }, cursor: first.next_cursor).call
    end
  end

  test "loads image associations only for returned cards rather than the entire candidate batch" do
    events = 25.times.map do |index|
      build_event(index: index).tap do |event|
        event.import_event_images.create!(
          source: "easyticket",
          image_type: "large",
          role: "cover",
          aspect_hint: "landscape",
          position: 0,
          image_url: "https://example.invalid/pager-#{index}.jpg"
        )
      end
    end
    image_count = 0
    subscriber = lambda do |notification|
      payload = notification.payload
      image_count += payload.fetch(:record_count) if payload[:class_name] == "ImportEventImage"
    end

    page = ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      Public::Events::HomepageLanePager.new(
        relation: Event.where(id: events.map(&:id)).includes(:import_event_images).order(:start_at, :id),
        context: @context,
        per_page: 10
      ).call
    end

    assert_equal events.first(10).map(&:id), page.events.map(&:id)
    assert_equal 10, image_count
    assert page.events.all? { |event| event.association(:import_event_images).loaded? }
    assert_equal (0...10).map { |index| "https://example.invalid/pager-#{index}.jpg" },
                 page.events.map { |event| event.import_event_images.first.image_url }
    assert_predicate page.next_cursor, :present?
  end

  private

  def pager(context: @context, cursor: nil)
    Public::Events::HomepageLanePager.new(
      relation: Event.published_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .where("source_fingerprint LIKE ?", "#{@source_prefix}%")
        .reorder(:start_at, :id),
      context: context,
      cursor: cursor,
      per_page: 10
    )
  end

  def build_event(index:, event_series: nil)
    Event.create!(
      slug: "homepage-lane-pager-#{index}-#{SecureRandom.hex(4)}",
      source_fingerprint: "#{@source_prefix}::#{index}",
      title: "Pager Event #{index}",
      artist_name: "Pager Artist #{index}",
      start_at: (index + 1).days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Club Zentral",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      event_series: event_series,
      event_series_assignment: ("manual" if event_series.present?),
      source_snapshot: {}
    )
  end
end
