require "test_helper"

class Merging::SyncFromImportsTest < ActiveSupport::TestCase
  setup do
    RawEventImport.delete_all
  end

  test "merges easyticket and eventim raw imports into a published event" do
    source_easyticket = import_sources(:one)
    source_eventim = import_sources(:two)

    RawEventImport.create!(
      import_source: source_easyticket,
      import_event_type: "easyticket",
      source_identifier: "merge-easy-1:2026-11-10",
      payload: {
        "event_id" => "merge-easy-1",
        "date_time" => "2026-11-10 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Band A",
        "title_2" => "Metal Night",
        "organizer_id" => "382",
        "price_start" => 59.45,
        "price_end" => 86.70,
        "description" => "<p>Easy Headline<br />Easy Line</p>",
        "ticket_url" => "https://example.com/easy",
        "data" => {
          "location" => {
            "name" => "Im Wizemann",
            "city" => "Stuttgart"
          },
          "images" => {
            "merge-easy-1" => {
              "large" => "https://example.com/easy.jpg"
            }
          }
        }
      }
    )

    RawEventImport.create!(
      import_source: source_eventim,
      import_event_type: "eventim",
      source_identifier: "merge-eventim-1:2026-11-10",
      payload: {
        "eventid" => "merge-eventim-1",
        "eventdate" => "2026-11-10",
        "eventtime" => "20:00",
        "eventplace" => "Stuttgart",
        "eventvenue" => "Im Wizemann",
        "eventname" => "Metal Night",
        "artistname" => "Band A",
        "promoterid" => "10135",
        "eventlink" => "https://example.com/eventim",
        "espicture_big" => "https://example.com/eventim.jpg",
        "pricecategory" => [
          { "price" => "58,84", "currency" => "EUR" },
          { "price" => "36,84", "currency" => "EUR" }
        ]
      }
    )

    result = Merging::SyncFromImports.new.call

    assert_equal 2, result.import_records_count
    assert_equal 1, result.groups_count

    event = Event.find_by!(artist_name: "Band A", start_at: Time.zone.local(2026, 11, 10, 20, 0, 0))
    assert_equal "easyticket", event.primary_source
    assert_equal "382", event.promoter_id
    assert_equal "published", event.status
    assert_equal true, event.auto_published
    assert_equal "Easy Headline\nEasy Line", event.event_info
    assert_equal 2, event.event_offers.count
    assert_equal "59,45 - 86,70 EUR", event.event_offers.find_by(source: "easyticket")&.ticket_price_text
    assert_equal "36,84 - 58,84 EUR", event.event_offers.find_by(source: "eventim")&.ticket_price_text
    assert_equal 2, event.import_event_images.count
    assert_equal 2, event.source_snapshot.fetch("sources").size
  end

  test "sets needs_review when merged raw imports do not provide an image" do
    RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "merge-no-image:2026-12-01",
      payload: {
        "event_id" => "merge-no-image",
        "date_time" => "2026-12-01 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "LKA Longhorn",
        "title_1" => "Band Without Image",
        "title_2" => "No Image Night"
      }
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Band Without Image")
    assert_equal "needs_review", event.status
    assert_equal false, event.auto_published
    assert_includes event.completeness_flags, "missing_image"
  end

  test "leaves doors_at empty when import does not provide a valid doors time" do
    RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "merge-no-doors:2026-12-02",
      payload: {
        "event_id" => "merge-no-doors",
        "date_time" => "2026-12-02 20:00:00",
        "doors_at" => "open end",
        "loc_city" => "Stuttgart",
        "loc_name" => "LKA Longhorn",
        "title_1" => "Band Without Doors",
        "title_2" => "No Doors Time",
        "data" => {
          "images" => {
            "merge-no-doors" => {
              "large" => "https://example.com/no-doors.jpg"
            }
          }
        }
      }
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Band Without Doors")
    assert_nil event.doors_at
  end

  test "deduplicates sources by normalized artist_name and start_at" do
    source_reservix = ImportSource.ensure_reservix_source!

    RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "dup-easy:2026-12-14",
      payload: {
        "event_id" => "dup-easy",
        "date_time" => "2026-12-14 19:30:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "CAFÉ DEL MUNDO",
        "title_2" => "Live"
      }
    )

    RawEventImport.create!(
      import_source: source_reservix,
      import_event_type: "reservix",
      source_identifier: "dup-reservix",
      payload: {
        "id" => "dup-reservix",
        "name" => "Live",
        "artist" => "Cafe del Mundo",
        "bookable" => true,
        "startdate" => "2026-12-14",
        "starttime" => "19:30",
        "affiliateSaleUrl" => "https://example.com/reservix",
        "references" => {
          "venue" => [ { "name" => "LKA Longhorn", "city" => "Stuttgart" } ],
          "image" => [
            {
              "url" => "https://example.com/reservix.jpg",
              "type" => 1
            }
          ]
        }
      }
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "CAFÉ DEL MUNDO", start_at: Time.zone.local(2026, 12, 14, 19, 30, 0))
    assert_equal 2, event.event_offers.count
  end

  test "incremental merge updates only the allowed event fields" do
    source = import_sources(:one)
    initial_time = Time.zone.parse("2026-03-14 09:00:00")
    incremental_time = Time.zone.parse("2026-03-14 11:00:00")

    first_raw = RawEventImport.create!(
      import_source: source,
      import_event_type: "easyticket",
      source_identifier: "update-easy:2026-12-20",
      payload: {
        "event_id" => "update-easy",
        "date_time" => "2026-12-20 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Band Update",
        "title_2" => "Original Title",
        "price_start" => 40,
        "price_end" => 50,
        "data" => {
          "images" => {
            "update-easy" => {
              "large" => "https://example.com/update.jpg"
            }
          }
        }
      }
    )
    first_raw.update_columns(created_at: initial_time, updated_at: initial_time)

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Band Update")
    event_id = event.id

    second_raw = RawEventImport.create!(
      import_source: source,
      import_event_type: "easyticket",
      source_identifier: "update-easy:2026-12-20",
      payload: {
        "event_id" => "update-easy",
        "date_time" => "2026-12-20 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Porsche Arena",
        "title_1" => "Band Update",
        "title_2" => "Changed Title",
        "badge_text" => "Ausverkauft fast",
        "price_start" => 45,
        "price_end" => 55,
        "data" => {
          "images" => {
            "update-easy" => {
              "large" => "https://example.com/update.jpg"
            }
          }
        }
      }
    )
    second_raw.update_columns(created_at: incremental_time, updated_at: incremental_time)

    result = Merging::SyncFromImports.new(last_run_at: Time.zone.parse("2026-03-14 10:00:00")).call

    updated_event = Event.find(event_id)
    assert_equal 1, result.events_updated_count
    assert_equal "Original Title", updated_event.title
    assert_equal "Porsche Arena", updated_event.venue
    assert_equal "Ausverkauft fast", updated_event.badge_text
    assert_equal BigDecimal("45"), updated_event.min_price
    assert_equal BigDecimal("55"), updated_event.max_price
  end

  test "incremental merge updates doors_at from current import data" do
    source = import_sources(:one)
    initial_time = Time.zone.parse("2026-03-14 09:00:00")
    incremental_time = Time.zone.parse("2026-03-14 11:00:00")

    first_raw = RawEventImport.create!(
      import_source: source,
      import_event_type: "easyticket",
      source_identifier: "doors-update:2026-12-20",
      payload: {
        "event_id" => "doors-update",
        "date_time" => "2026-12-20 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Band Doors",
        "title_2" => "Original Title",
        "data" => {
          "images" => {
            "doors-update" => {
              "large" => "https://example.com/doors-update.jpg"
            }
          }
        }
      }
    )
    first_raw.update_columns(created_at: initial_time, updated_at: initial_time)

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Band Doors")
    event_id = event.id
    event.update!(doors_at: Time.zone.local(2026, 12, 20, 17, 0, 0))

    second_raw = RawEventImport.create!(
      import_source: source,
      import_event_type: "easyticket",
      source_identifier: "doors-update:2026-12-20",
      payload: {
        "event_id" => "doors-update",
        "date_time" => "2026-12-20 20:00:00",
        "doors_at" => "18:30",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Band Doors",
        "title_2" => "Original Title",
        "data" => {
          "images" => {
            "doors-update" => {
              "large" => "https://example.com/doors-update.jpg"
            }
          }
        }
      }
    )
    second_raw.update_columns(created_at: incremental_time, updated_at: incremental_time)

    Merging::SyncFromImports.new(last_run_at: Time.zone.parse("2026-03-14 10:00:00")).call

    updated_event = Event.find(event_id)
    assert_equal Time.zone.local(2026, 12, 20, 18, 30, 0), updated_event.doors_at
  end

  test "incremental merge updates start_at by matching the prior source snapshot" do
    source = import_sources(:one)
    initial_time = Time.zone.parse("2026-03-14 09:00:00")
    incremental_time = Time.zone.parse("2026-03-14 11:00:00")

    first_raw = RawEventImport.create!(
      import_source: source,
      import_event_type: "easyticket",
      source_identifier: "move-time:2026-12-21",
      payload: {
        "event_id" => "move-time",
        "date_time" => "2026-12-21 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Band Move",
        "title_2" => "Time Shift",
        "data" => {
          "images" => {
            "move-time" => {
              "large" => "https://example.com/move-time.jpg"
            }
          }
        }
      }
    )
    first_raw.update_columns(created_at: initial_time, updated_at: initial_time)

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Band Move")
    event_id = event.id

    second_raw = RawEventImport.create!(
      import_source: source,
      import_event_type: "easyticket",
      source_identifier: "move-time:2026-12-21",
      payload: {
        "event_id" => "move-time",
        "date_time" => "2026-12-21 21:15:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Band Move",
        "title_2" => "Time Shift",
        "data" => {
          "images" => {
            "move-time" => {
              "large" => "https://example.com/move-time.jpg"
            }
          }
        }
      }
    )
    second_raw.update_columns(created_at: incremental_time, updated_at: incremental_time)

    Merging::SyncFromImports.new(last_run_at: Time.zone.parse("2026-03-14 10:00:00")).call

    updated_event = Event.find(event_id)
    assert_equal Time.zone.local(2026, 12, 21, 21, 15, 0), updated_event.start_at
    assert_equal updated_event.source_fingerprint,
      [
        Merging::SyncFromImports::DuplicationKey.normalize_artist_name("Band Move"),
        updated_event.start_at.iso8601
      ].join("::")
  end

  test "uses easyticket detail_payload images when payload has no image" do
    source_easyticket = import_sources(:one)

    RawEventImport.create!(
      import_source: source_easyticket,
      import_event_type: "easyticket",
      source_identifier: "merge-easy-detail-image:2026-12-24",
      payload: {
        "event_id" => "merge-easy-detail-image",
        "date_time" => "2026-12-24 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Band Detail",
        "title_2" => "Detail Image Night",
        "ticket_url" => "https://example.com/easy-detail"
      },
      detail_payload: {
        "data" => {
          "images" => [
            {
              "paths" => [
                { "type" => "detail_path", "url" => "https://example.com/easy-detail-image.jpg" }
              ]
            }
          ]
        }
      }
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Band Detail")
    assert_equal "published", event.status
    assert_equal [ "https://example.com/easy-detail-image.jpg" ], event.import_event_images.ordered.pluck(:image_url)
  end
end
