require "test_helper"

class EventTest < ActiveSupport::TestCase
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
end
