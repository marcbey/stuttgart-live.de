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
end
