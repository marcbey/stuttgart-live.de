require "test_helper"

class Merging::SyncFromImportsTest < ActiveSupport::TestCase
  test "merges active easyticket and eventim records into a published event" do
    source_easyticket = import_sources(:one)
    source_eventim = import_sources(:two)

    date = Date.new(2026, 11, 10)

    easy_record = source_easyticket.easyticket_import_events.create!(
      external_event_id: "merge-easy-1",
      concert_date: date,
      city: "Stuttgart",
      venue_name: "Im Wizemann",
      title: "Metal Night",
      artist_name: "Band A",
      organizer_name: "SKS Michael Russ GmbH",
      organizer_id: "382",
      concert_date_label: "10.11.2026",
      venue_label: "Stuttgart, Im Wizemann",
      dump_payload: {},
      detail_payload: {},
      ticket_url: "https://example.com/easy",
      is_active: true,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      source_payload_hash: "hash-easy-1"
    )

    easy_record.import_event_images.create!(
      source: "easyticket",
      image_type: "large",
      image_url: "https://example.com/easy.jpg",
      role: "cover",
      aspect_hint: "landscape",
      position: 0
    )

    eventim_record = source_eventim.eventim_import_events.create!(
      external_event_id: "merge-eventim-1",
      concert_date: date,
      city: "Stuttgart",
      venue_name: "Im Wizemann",
      title: "Metal Night",
      artist_name: "Band A",
      promoter_id: "10135",
      concert_date_label: "10.11.2026",
      venue_label: "Stuttgart, Im Wizemann",
      dump_payload: {},
      detail_payload: {},
      ticket_url: "https://example.com/eventim",
      is_active: true,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      source_payload_hash: "hash-eventim-1"
    )

    eventim_record.import_event_images.create!(
      source: "eventim",
      image_type: "espicture_big",
      image_url: "https://example.com/eventim.jpg",
      role: "cover",
      aspect_hint: "landscape",
      position: 0
    )

    result = Merging::SyncFromImports.new.call

    assert result.groups_count.positive?
    assert result.import_records_count.positive?

    event = Event.find_by(artist_name: "Band A", start_at: Time.zone.local(2026, 11, 10, 20, 0, 0))
    assert event.present?
    assert_equal "eventim", event.primary_source
    assert_equal "SKS Michael Russ GmbH", event.organizer_name
    assert_equal "10135", event.promoter_id
    assert_equal "published", event.status
    assert_equal true, event.auto_published
    assert_equal 2, event.event_offers.count
    assert_equal 2, event.import_event_images.count

    second_result = Merging::SyncFromImports.new.call
    assert_equal 0, second_result.events_created_count
    assert_equal 0, second_result.events_updated_count
    assert_equal 0, second_result.offers_upserted_count
  end

  test "sets needs_review when import event has no image" do
    source_easyticket = import_sources(:one)
    date = Date.new(2026, 12, 1)

    source_easyticket.easyticket_import_events.create!(
      external_event_id: "merge-easy-no-image",
      concert_date: date,
      city: "Stuttgart",
      venue_name: "LKA Longhorn",
      title: "No Image Night",
      artist_name: "Band Without Image",
      organizer_name: "SKS Michael Russ GmbH",
      organizer_id: "382",
      concert_date_label: "01.12.2026",
      venue_label: "Stuttgart, LKA Longhorn",
      dump_payload: {},
      detail_payload: {},
      ticket_url: "https://example.com/easy-no-image",
      is_active: true,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      source_payload_hash: "hash-easy-no-image"
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by(artist_name: "Band Without Image", start_at: Time.zone.local(2026, 12, 1, 20, 0, 0))
    assert event.present?
    assert_equal "needs_review", event.status
    assert_equal false, event.auto_published
    assert_includes event.completeness_flags, "missing_image"
  end
end
