require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    @fixture_path = Rails.root.join("test/fixtures/files/test_image.png")
  end

  test "splits combined title into artist and tour when artist still equals title" do
    event = Event.new(
      artist_name: "WILHELMINE - magisch Tour 2026",
      title: "WILHELMINE - magisch Tour 2026",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal "WILHELMINE", event.artist_name
    assert_equal "magisch Tour 2026", event.title
  end

  test "removes artist prefix from title when artist is already set separately" do
    event = Event.new(
      artist_name: "WILHELMINE",
      title: "WILHELMINE - magisch Tour 2026",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal "WILHELMINE", event.artist_name
    assert_equal "magisch Tour 2026", event.title
  end

  test "keeps title unchanged when it does not start with the artist name" do
    event = Event.new(
      artist_name: "WILHELMINE",
      title: "Special Guest Night - magisch Tour 2026",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal "WILHELMINE", event.artist_name
    assert_equal "Special Guest Night - magisch Tour 2026", event.title
  end

  test "normalizes kulturquartier venue name without proton" do
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Kulturquartier - PROTON",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal "Kulturquartier", event.venue
  end

  test "allows blank city and normalizes it to nil" do
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "   ",
      status: "needs_review"
    )

    assert event.valid?
    assert_nil event.city
  end

  test "syncs publication fields for published events without overriding existing values" do
    publisher = users(:one)
    published_at = 2.days.ago.change(usec: 0)
    event = events(:published_one)
    event.published_at = published_at
    event.published_by = publisher

    event.sync_publication_fields(user: users(:blogger))

    assert_equal published_at, event.published_at
    assert_equal publisher, event.published_by
  end

  test "syncs publication fields by clearing them for unpublished events" do
    event = events(:published_one)
    event.status = "needs_review"

    event.sync_publication_fields(user: users(:one))

    assert_nil event.published_at
    assert_nil event.published_by
  end

  test "publish_now persists a manual publication state" do
    event = events(:needs_review_one)

    freeze_time do
      event.publish_now!(user: users(:one), auto_published: false)

      assert_equal "published", event.status
      assert_equal false, event.auto_published
      assert_equal Time.current, event.published_at
      assert_equal users(:one), event.published_by
    end
  end

  test "unpublish clears persisted publication fields" do
    event = events(:published_one)

    event.unpublish!(status: "ready_for_publish", auto_published: false)

    assert_equal "ready_for_publish", event.status
    assert_equal false, event.auto_published
    assert_nil event.published_at
    assert_nil event.published_by
  end

  test "preferred_ticket_offer uses loaded offers without extra queries" do
    event = Event.includes(:event_offers).find(events(:published_one).id)
    expected_offer = event_offers(:published_one_offer)

    queries = capture_sql_queries { assert_equal expected_offer, event.preferred_ticket_offer }

    assert_equal 0, queries
  end

  test "primary_genre uses loaded genres without extra queries" do
    event = Event.includes(:genres).find(events(:published_one).id)
    expected_genre = genres(:rock)

    queries = capture_sql_queries { assert_equal expected_genre, event.primary_genre }

    assert_equal 0, queries
  end

  test "image_for uses loaded import images without extra queries" do
    event = Event.includes(:event_images, :import_event_images).find(events(:published_one).id)
    expected_image = import_event_images(:published_cover)

    queries = capture_sql_queries do
      assert_equal expected_image, event.image_for(slot: :grid_default, breakpoint: :mobile)
    end

    assert_equal 0, queries
  end

  test "image_for uses loaded event images without extra queries" do
    event = events(:published_one)
    event_image = create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO)
    loaded_event = Event.includes(:event_images, :import_event_images).find(event.id)

    queries = capture_sql_queries do
      assert_equal event_image, loaded_event.image_for(slot: :detail_hero, breakpoint: :desktop)
    end

    assert_equal 0, queries
  end

  test "image_url_for returns optimized representation path for editorial images" do
    event = events(:published_one)
    event_image = create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO)

    assert_equal(
      Rails.application.routes.url_helpers.rails_storage_proxy_path(event_image.processed_optimized_variant, only_path: true),
      event.image_url_for(slot: :detail_hero, breakpoint: :desktop)
    )
  end

  private

  def create_event_image(event:, purpose:)
    image = EventImage.new(
      event: event,
      purpose: purpose,
      alt_text: "Alt",
      sub_text: "Sub"
    )
    image.file.attach(
      io: StringIO.new(File.binread(@fixture_path)),
      filename: "test_image.png",
      content_type: "image/png"
    )
    image.save!
    image
  end

  def capture_sql_queries
    queries = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"
      next if payload[:cached]
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/)

      queries += 1
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end

    queries
  end
end
