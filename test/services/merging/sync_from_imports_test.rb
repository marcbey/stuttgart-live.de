require "test_helper"

class Merging::SyncFromImportsTest < ActiveSupport::TestCase
  test "merges active easyticket and eventim records into a published event" do
    source_easyticket = import_sources(:one)
    source_eventim = import_sources(:two)

    date = Date.new(2026, 11, 10)

    source_easyticket.easyticket_import_events.create!(
      external_event_id: "merge-easy-1",
      concert_date: date,
      city: "Stuttgart",
      venue_name: "Im Wizemann",
      title: "Metal Night",
      artist_name: "Band A",
      concert_date_label: "10.11.2026",
      venue_label: "Stuttgart, Im Wizemann",
      dump_payload: {},
      detail_payload: {},
      ticket_url: "https://example.com/easy",
      image_url: "https://example.com/easy.jpg",
      is_active: true,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      source_payload_hash: "hash-easy-1"
    )

    source_eventim.eventim_import_events.create!(
      external_event_id: "merge-eventim-1",
      concert_date: date,
      city: "Stuttgart",
      venue_name: "Im Wizemann",
      title: "Metal Night",
      artist_name: "Band A",
      concert_date_label: "10.11.2026",
      venue_label: "Stuttgart, Im Wizemann",
      dump_payload: {},
      detail_payload: {},
      ticket_url: "https://example.com/eventim",
      image_url: "https://example.com/eventim.jpg",
      is_active: true,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      source_payload_hash: "hash-eventim-1"
    )

    result = Merging::SyncFromImports.new.call

    assert result.groups_count.positive?

    event = Event.find_by(artist_name: "Band A", start_at: Time.zone.local(2026, 11, 10, 20, 0, 0))
    assert event.present?
    assert_equal "eventim", event.primary_source
    assert_equal "published", event.status
    assert_equal true, event.auto_published
    assert_equal 2, event.event_offers.count
  end
end
