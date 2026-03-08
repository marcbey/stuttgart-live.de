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
      dump_payload: {
        "date_time" => "2026-11-10 20:00:00",
        "price_start" => 59.45,
        "price_end" => 86.70,
        "description" => "<p>Easy Headline<br />Easy Line</p>"
      },
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
      dump_payload: {
        "pricecategory" => [
          { "price" => "58,84", "currency" => "EUR" },
          { "price" => "47,84", "currency" => "EUR" },
          { "price" => "36,84", "currency" => "EUR" }
        ],
        "estext" => "Eventim fallback text"
      },
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
    assert_equal "easyticket", event.primary_source
    assert_equal "382", event.promoter_id
    assert_equal "published", event.status
    assert_equal true, event.auto_published
    assert_equal 2, event.event_offers.count
    assert_equal "59,45 - 86,70 EUR", event.event_offers.find_by(source: "easyticket")&.ticket_price_text
    assert_equal "36,84 - 58,84 EUR", event.event_offers.find_by(source: "eventim")&.ticket_price_text
    assert_equal "Easy Headline\nEasy Line", event.event_info
    assert_equal 2, event.import_event_images.count
    assert_equal 1, event.event_change_logs.where(action: "merged_create").count
    assert_equal 0, event.event_change_logs.where(action: "merged_update").count

    second_result = Merging::SyncFromImports.new.call
    assert_equal 0, second_result.events_created_count
    assert_equal 0, second_result.events_updated_count
    assert_equal 0, second_result.offers_upserted_count
    assert_equal 1, event.reload.event_change_logs.where(action: "merged_create").count
    assert_equal 0, event.event_change_logs.where(action: "merged_update").count
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

  test "uses easyticket dump_payload date_time as event begin time" do
    source_easyticket = import_sources(:one)
    date = Date.new(2026, 12, 2)

    source_easyticket.easyticket_import_events.create!(
      external_event_id: "merge-easy-begin-time",
      concert_date: date,
      city: "Stuttgart",
      venue_name: "LKA Longhorn",
      title: "Begin Time Night",
      artist_name: "Band Begin Easy",
      organizer_name: "SKS Michael Russ GmbH",
      organizer_id: "382",
      concert_date_label: "02.12.2026",
      venue_label: "Stuttgart, LKA Longhorn",
      dump_payload: { "date_time" => "2026-12-02 19:30:00" },
      detail_payload: {},
      ticket_url: "https://example.com/easy-begin-time",
      is_active: true,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      source_payload_hash: "hash-easy-begin-time"
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by(artist_name: "Band Begin Easy")
    assert event.present?
    assert_equal Time.zone.local(2026, 12, 2, 19, 30, 0), event.start_at
  end

  test "uses eventim dump_payload eventtime as event begin time" do
    source_eventim = import_sources(:two)
    date = Date.new(2026, 12, 3)

    source_eventim.eventim_import_events.create!(
      external_event_id: "merge-eventim-begin-time",
      concert_date: date,
      city: "Stuttgart",
      venue_name: "Porsche Arena",
      title: "Begin Time Gala",
      artist_name: "Band Begin Eventim",
      promoter_id: "10135",
      concert_date_label: "03.12.2026",
      venue_label: "Stuttgart, Porsche Arena",
      dump_payload: { "eventtime" => "18:45" },
      detail_payload: {},
      ticket_url: "https://example.com/eventim-begin-time",
      is_active: true,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      source_payload_hash: "hash-eventim-begin-time"
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by(artist_name: "Band Begin Eventim")
    assert event.present?
    assert_equal Time.zone.local(2026, 12, 3, 18, 45, 0), event.start_at
  end

  test "uses eventim pricecategory object for ticket price text" do
    source_eventim = import_sources(:two)
    date = Date.new(2026, 12, 4)

    source_eventim.eventim_import_events.create!(
      external_event_id: "merge-eventim-price-object",
      concert_date: date,
      city: "Stuttgart",
      venue_name: "Porsche Arena",
      title: "Price Object Show",
      artist_name: "Band Price Object",
      promoter_id: "10135",
      concert_date_label: "04.12.2026",
      venue_label: "Stuttgart, Porsche Arena",
      dump_payload: {
        "eventtime" => "19:15",
        "pricecategory" => { "price" => "72,50", "currency" => "EUR" }
      },
      detail_payload: {},
      ticket_url: "https://example.com/eventim-price-object",
      is_active: true,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      source_payload_hash: "hash-eventim-price-object"
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by(artist_name: "Band Price Object")
    assert event.present?
    offer = event.event_offers.find_by(source: "eventim")
    assert_equal "72,50 EUR", offer&.ticket_price_text
  end

  test "uses eventim estext as event description when easyticket text is missing" do
    source_eventim = import_sources(:two)
    date = Date.new(2026, 12, 5)

    source_eventim.eventim_import_events.create!(
      external_event_id: "merge-eventim-description",
      concert_date: date,
      city: "Stuttgart",
      venue_name: "Porsche Arena",
      title: "Description Show",
      artist_name: "Band Description Eventim",
      promoter_id: "10135",
      concert_date_label: "05.12.2026",
      venue_label: "Stuttgart, Porsche Arena",
      dump_payload: {
        "eventtime" => "20:00",
        "estext" => "Eventim Description<br>Line 2"
      },
      detail_payload: {},
      ticket_url: "https://example.com/eventim-description",
      is_active: true,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      source_payload_hash: "hash-eventim-description"
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by(artist_name: "Band Description Eventim")
    assert event.present?
    assert_equal "Eventim Description\nLine 2", event.event_info
  end
end
