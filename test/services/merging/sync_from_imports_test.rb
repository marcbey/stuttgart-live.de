require "test_helper"

class Merging::SyncFromImportsTest < ActiveSupport::TestCase
  setup do
    RawEventImport.delete_all
    AppSetting.find_or_initialize_by(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY).update!(value: false)
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.reset_cache!
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
    assert_nil event.promoter_name
    assert_equal "published", event.status
    assert_equal true, event.auto_published
    assert_equal "Easy Headline\nEasy Line", event.event_info
    assert_equal 2, event.event_offers.count
    assert_equal "59,45 - 86,70 EUR", event.event_offers.find_by(source: "easyticket")&.ticket_price_text
    assert_equal "36,84 - 58,84 EUR", event.event_offers.find_by(source: "eventim")&.ticket_price_text
    assert_equal 2, event.import_event_images.count
    assert_equal 2, event.source_snapshot.fetch("sources").size
  end

  test "uses easyticket payload id for ticket url when title_3 is descriptive text" do
    source_easyticket = import_sources(:one)

    RawEventImport.create!(
      import_source: source_easyticket,
      import_event_type: "easyticket",
      source_identifier: "104364:2026-06-16",
      payload: {
        "id" => "105758",
        "event_id" => "104364",
        "title_3" => "The Beast Goes On",
        "date_time" => "2026-06-16 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Goldmarks",
        "title_1" => "Starbenders",
        "title_2" => "The Beast goes on Tour",
        "organizer_id" => "382"
      }
    )

    begin
      original_ticket_base_url = AppConfig.method(:easyticket_ticket_link_event_base_url)
      AppConfig.define_singleton_method(:easyticket_ticket_link_event_base_url) { "https://tickets.example/event/{event_id}" }
      Merging::SyncFromImports.new.call
    ensure
      AppConfig.define_singleton_method(:easyticket_ticket_link_event_base_url, original_ticket_base_url) if original_ticket_base_url
    end

    event = Event.find_by!(artist_name: "Starbenders", start_at: Time.zone.local(2026, 6, 16, 20, 0, 0))
    offer = event.event_offers.find_by!(source: "easyticket")

    assert_equal "104364", offer.source_event_id
    assert_equal "https://tickets.example/event/105758", offer.ticket_url
  end

  test "persists canceled availability from eventim status codes separately from sold out" do
    RawEventImport.create!(
      import_source: import_sources(:two),
      import_event_type: "eventim",
      source_identifier: "merge-eventim-canceled:2026-05-23",
      payload: {
        "eventid" => "merge-eventim-canceled",
        "eventdate" => "2026-05-23",
        "eventtime" => "20:00",
        "eventplace" => "Stuttgart",
        "eventvenue" => "Schräglage",
        "eventname" => "Canceled Tour",
        "artistname" => "Canceled Artist",
        "eventStatus" => "1",
        "eventlink" => "https://example.com/eventim-canceled",
        "espicture_big" => "https://example.com/eventim-canceled.jpg",
        "pricecategory" => [
          { "price" => "31,00", "currency" => "EUR", "inventory" => "nicht buchbar" }
        ]
      }
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Canceled Artist", start_at: Time.zone.local(2026, 5, 23, 20, 0, 0))
    offer = event.event_offers.find_by!(source: "eventim")

    assert_equal true, offer.sold_out
    assert_equal "canceled", offer.metadata["availability_status"]
    assert_equal "1", offer.metadata["source_status_code"]
    assert_predicate event, :public_canceled?
    assert_not event.public_sold_out?
    assert_nil event.public_ticket_offer
    assert_equal "Abgesagt", event.public_ticket_status_label
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

  test "uses reservix public organizer name for promoter_name while keeping promoter_id from the prioritized source" do
    source_reservix = ImportSource.ensure_reservix_source!

    RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "merge-name-easy:2026-12-08",
      payload: {
        "event_id" => "merge-name-easy",
        "date_time" => "2026-12-08 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Band Named",
        "title_2" => "Named Night",
        "organizer_id" => "382",
        "ticket_url" => "https://example.com/easy-name",
        "data" => {
          "images" => {
            "merge-name-easy" => {
              "large" => "https://example.com/easy-name.jpg"
            }
          }
        }
      }
    )

    RawEventImport.create!(
      import_source: source_reservix,
      import_event_type: "reservix",
      source_identifier: "merge-name-reservix",
      payload: {
        "id" => "merge-name-reservix",
        "name" => "Named Night",
        "artist" => "Band Named",
        "bookable" => true,
        "startdate" => "2026-12-08",
        "starttime" => "20:00",
        "affiliateSaleUrl" => "https://example.com/reservix-name",
        "publicOrganizerName" => "Reservix Veranstalter",
        "references" => {
          "venue" => [ { "name" => "Im Wizemann", "city" => "Stuttgart" } ],
          "organizer" => [ { "id" => 7295, "name" => "Abweichender Organizer" } ],
          "image" => [
            {
              "url" => "https://example.com/reservix-name.jpg",
              "type" => 1
            }
          ]
        }
      }
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Band Named", start_at: Time.zone.local(2026, 12, 8, 20, 0, 0))
    assert_equal "382", event.promoter_id
    assert_equal "Reservix Veranstalter", event.promoter_name

    reservix_snapshot = event.source_snapshot.fetch("sources").find { |source| source["source"] == "reservix" }
    assert_equal "Reservix Veranstalter", reservix_snapshot["promoter_name"]
  end

  test "does not overwrite promoter_name on later merges" do
    source_reservix = ImportSource.ensure_reservix_source!
    source_identifier = "merge-promoter-name-stable"

    raw_import = RawEventImport.create!(
      import_source: source_reservix,
      import_event_type: "reservix",
      source_identifier: source_identifier,
      payload: {
        "id" => "merge-promoter-name-stable",
        "name" => "Stable Night",
        "artist" => "Stable Artist",
        "bookable" => true,
        "startdate" => "2026-12-09",
        "starttime" => "20:00",
        "affiliateSaleUrl" => "https://example.com/reservix-stable",
        "publicOrganizerName" => "Erster Veranstalter",
        "references" => {
          "venue" => [ { "name" => "Im Wizemann", "city" => "Stuttgart" } ],
          "image" => [
            {
              "url" => "https://example.com/reservix-stable.jpg",
              "type" => 1
            }
          ]
        }
      }
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Stable Artist")
    assert_equal "Erster Veranstalter", event.promoter_name

    raw_import.update!(
      payload: raw_import.payload.merge(
        "publicOrganizerName" => "Zweiter Veranstalter"
      )
    )

    Merging::SyncFromImports.new.call

    assert_equal "Erster Veranstalter", event.reload.promoter_name
    reservix_snapshot = event.source_snapshot.fetch("sources").find { |source| source["source"] == "reservix" }
    assert_equal "Zweiter Veranstalter", reservix_snapshot["promoter_name"]
  end

  test "publishes existing needs_review event when a later merge provides the missing image and completeness is restored" do
    raw_import = RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "merge-review-to-ready:2026-12-03",
      payload: {
        "event_id" => "merge-review-to-ready",
        "date_time" => "2026-12-03 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Band Review Ready",
        "title_2" => "Late Image Night",
        "ticket_url" => "https://example.com/review-ready"
      }
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Band Review Ready")
    assert_equal "needs_review", event.status
    assert_equal [ "missing_image" ], event.completeness_flags

    raw_import.update!(
      payload: raw_import.payload.merge(
        "data" => {
          "images" => {
            "merge-review-to-ready" => {
              "large" => "https://example.com/review-ready.jpg"
            }
          }
        }
      )
    )

    Merging::SyncFromImports.new.call

    event.reload
    assert_equal "published", event.status
    assert_equal true, event.auto_published
    assert_nil event.published_at
    assert_empty event.completeness_flags
    assert_equal 1, event.import_event_images.count
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

  test "does not similarity-match artist variants when similarity matching is disabled" do
    AppSetting.find_or_initialize_by(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY).update!(value: false)
    AppSetting.reset_cache!

    RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "similarity-off-easy:2026-12-18",
      payload: {
        "event_id" => "similarity-off-easy",
        "date_time" => "2026-12-18 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Gregory Porter",
        "title_2" => "Jazz Night"
      }
    )

    RawEventImport.create!(
      import_source: import_sources(:two),
      import_event_type: "eventim",
      source_identifier: "similarity-off-eventim:2026-12-18",
      payload: {
        "eventid" => "similarity-off-eventim",
        "eventdate" => "2026-12-18",
        "eventtime" => "20:00",
        "eventplace" => "Stuttgart",
        "eventvenue" => "LKA Longhorn",
        "eventname" => "Jazz Night",
        "artistname" => "Gregory Porter & Orchestra"
      }
    )

    result = Merging::SyncFromImports.new.call

    assert_equal 2, result.groups_count
    assert_equal 2, Event.where(start_at: Time.zone.local(2026, 12, 18, 20, 0, 0)).count
  end

  test "similarity-matches artist variants when enabled" do
    AppSetting.find_or_initialize_by(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY).update!(value: true)
    AppSetting.reset_cache!
    merge_run_id = 101

    RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "similarity-on-easy:2026-12-19",
      payload: {
        "event_id" => "similarity-on-easy",
        "date_time" => "2026-12-19 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Vier Pianisten",
        "title_2" => "Konzertabend"
      }
    )

    RawEventImport.create!(
      import_source: import_sources(:two),
      import_event_type: "eventim",
      source_identifier: "similarity-on-eventim:2026-12-19",
      payload: {
        "eventid" => "similarity-on-eventim",
        "eventdate" => "2026-12-19",
        "eventtime" => "20:00",
        "eventplace" => "Stuttgart",
        "eventvenue" => "LKA Longhorn",
        "eventname" => "Konzertabend",
        "artistname" => "Vier Pianisten - Ein Konzert"
      }
    )

    result = Merging::SyncFromImports.new(merge_run_id: merge_run_id).call

    assert_equal 2, result.import_records_count
    assert_equal 2, result.groups_count
    assert_equal 1, result.duplicate_matches_count
    event = Event.find_by!(start_at: Time.zone.local(2026, 12, 19, 20, 0, 0))

    assert_equal 1, Event.where(start_at: Time.zone.local(2026, 12, 19, 20, 0, 0)).count
    assert_equal [ "merged_create" ], EventChangeLog.where(
      event_id: event.id,
      action: [ "merged_create", "merged_update" ]
    ).where("metadata ->> 'merge_run_id' = ?", merge_run_id.to_s).order(:id).pluck(:action)
  end

  test "similarity match keeps easyticket as primary source over existing eventim event" do
    AppSetting.find_or_initialize_by(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY).update!(value: true)
    AppSetting.reset_cache!

    source_eventim = import_sources(:two)
    source_easyticket = import_sources(:one)
    eventim_time = Time.zone.parse("2026-03-18 10:00:00")
    easyticket_time = Time.zone.parse("2026-03-18 11:00:00")

    eventim_raw = RawEventImport.create!(
      import_source: source_eventim,
      import_event_type: "eventim",
      source_identifier: "priority-eventim:2026-12-16",
      payload: {
        "eventid" => "priority-eventim",
        "eventdate" => "2026-12-16",
        "eventtime" => "20:00",
        "eventplace" => "Stuttgart",
        "eventvenue" => "LKA Longhorn",
        "eventname" => "Gregory Porter & Orchestra - The Spirit Of Christmas Tour 2026",
        "artistname" => "Gregory Porter",
        "eventlink" => "https://example.com/eventim-priority",
        "espicture_big" => "https://example.com/gregory-eventim.jpg"
      }
    )
    eventim_raw.update_columns(created_at: eventim_time, updated_at: eventim_time)

    Merging::SyncFromImports.new.call

    easyticket_raw = RawEventImport.create!(
      import_source: source_easyticket,
      import_event_type: "easyticket",
      source_identifier: "priority-easy:2026-12-16",
      payload: {
        "event_id" => "priority-easy",
        "date_time" => "2026-12-16 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Gregory Porter & Orchestra",
        "title_2" => "THE SPIRIT OF CHRISTMAS TOUR 2026",
        "ticket_url" => "https://example.com/easy-priority",
        "data" => {
          "images" => {
            "priority-easy" => {
              "large" => "https://example.com/gregory-easy.jpg"
            }
          }
        }
      }
    )
    easyticket_raw.update_columns(created_at: easyticket_time, updated_at: easyticket_time)

    Merging::SyncFromImports.new(last_run_at: eventim_time + 30.minutes).call

    event = Event.find_by!(start_at: Time.zone.local(2026, 12, 16, 20, 0, 0))
    assert_equal "easyticket", event.primary_source
    assert_equal %w[easyticket eventim], event.event_offers.order(:priority_rank, :id).pluck(:source)
    assert_equal %w[easyticket eventim], event.source_snapshot.fetch("sources").map { |source| source.fetch("source") }
  end

  test "incremental merge updates only the allowed event fields" do
    source = import_sources(:one)
    initial_time = Time.zone.parse("2026-03-14 09:00:00")
    incremental_time = Time.zone.parse("2026-03-14 11:00:00")
    initial_merge_run_id = 201
    incremental_merge_run_id = 202

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

    Merging::SyncFromImports.new(merge_run_id: initial_merge_run_id).call

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

    result = Merging::SyncFromImports.new(
      merge_run_id: incremental_merge_run_id,
      last_run_at: Time.zone.parse("2026-03-14 10:00:00")
    ).call

    updated_event = Event.find(event_id)
    assert_equal 1, result.events_updated_count
    assert_equal "Original Title", updated_event.title
    assert_equal "Porsche Arena", updated_event.venue
    assert_equal "Ausverkauft fast", updated_event.badge_text
    assert_equal BigDecimal("45"), updated_event.min_price
    assert_equal BigDecimal("55"), updated_event.max_price
    assert_equal [ "merged_update" ], EventChangeLog.where(
      event_id: updated_event.id,
      action: [ "merged_create", "merged_update" ]
    ).where("metadata ->> 'merge_run_id' = ?", incremental_merge_run_id.to_s).order(:id).pluck(:action)
  end

  test "existing events can still log multiple merged_update entries within the same run" do
    AppSetting.find_or_initialize_by(key: AppSetting::MERGE_ARTIST_SIMILARITY_MATCHING_ENABLED_KEY).update!(value: true)
    AppSetting.reset_cache!

    source_easyticket = import_sources(:one)
    source_eventim = import_sources(:two)
    initial_time = Time.zone.parse("2026-03-18 09:00:00")
    incremental_time = Time.zone.parse("2026-03-18 11:00:00")

    initial_raw = RawEventImport.create!(
      import_source: source_easyticket,
      import_event_type: "easyticket",
      source_identifier: "multi-update-easy:2026-12-26",
      payload: {
        "event_id" => "multi-update-easy",
        "date_time" => "2026-12-26 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Im Wizemann",
        "title_1" => "Gregory Porter",
        "title_2" => "Soul Night",
        "data" => {
          "images" => {
            "multi-update-easy" => {
              "large" => "https://example.com/multi-update-easy.jpg"
            }
          }
        }
      }
    )
    initial_raw.update_columns(created_at: initial_time, updated_at: initial_time)

    Merging::SyncFromImports.new(merge_run_id: 301).call

    incremental_easy = RawEventImport.create!(
      import_source: source_easyticket,
      import_event_type: "easyticket",
      source_identifier: "multi-update-easy:2026-12-26",
      payload: {
        "event_id" => "multi-update-easy",
        "date_time" => "2026-12-26 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "Porsche Arena",
        "title_1" => "Gregory Porter",
        "title_2" => "Soul Night",
        "badge_text" => "Fast ausverkauft",
        "data" => {
          "images" => {
            "multi-update-easy" => {
              "large" => "https://example.com/multi-update-easy.jpg"
            }
          }
        }
      }
    )
    incremental_easy.update_columns(created_at: incremental_time, updated_at: incremental_time)

    incremental_eventim = RawEventImport.create!(
      import_source: source_eventim,
      import_event_type: "eventim",
      source_identifier: "multi-update-eventim:2026-12-26",
      payload: {
        "eventid" => "multi-update-eventim",
        "eventdate" => "2026-12-26",
        "eventtime" => "20:00",
        "eventplace" => "Stuttgart",
        "eventvenue" => "Porsche Arena",
        "eventname" => "Soul Night",
        "artistname" => "Gregory Porter & Orchestra",
        "eventlink" => "https://example.com/multi-update-eventim",
        "espicture_big" => "https://example.com/multi-update-eventim.jpg"
      }
    )
    incremental_eventim.update_columns(created_at: incremental_time + 1.minute, updated_at: incremental_time + 1.minute)

    Merging::SyncFromImports.new(
      merge_run_id: 302,
      last_run_at: Time.zone.parse("2026-03-18 10:00:00")
    ).call

    event = Event.find_by!(artist_name: "Gregory Porter", start_at: Time.zone.local(2026, 12, 26, 20, 0, 0))
    logs = EventChangeLog.where(
      event_id: event.id,
      action: [ "merged_create", "merged_update" ]
    ).where("metadata ->> 'merge_run_id' = ?", "302")

    assert_equal 2, logs.count
    assert_equal [ "merged_update" ], logs.distinct.order(:action).pluck(:action)
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

  test "prefers the event with the exact source fingerprint when a stale match points elsewhere" do
    source = import_sources(:two)
    target_start_at = Time.zone.local(2027, 4, 26, 19, 30, 0)
    target_fingerprint = [
      Merging::SyncFromImports::DuplicationKey.normalize_artist_name("This is THE GREATEST SHOW!"),
      target_start_at.iso8601
    ].join("::")

    stale_event = Event.create!(
      artist_name: "This is THE GREATEST SHOW!",
      title: "Die größten Musical Hits aller Zeiten - Tour 2027",
      start_at: Time.zone.local(2027, 4, 5, 19, 30, 0),
      venue: "Stage Apollo Theater Stuttgart",
      city: "Stuttgart",
      status: "published",
      primary_source: "eventim",
      source_fingerprint: [
        Merging::SyncFromImports::DuplicationKey.normalize_artist_name("This is THE GREATEST SHOW!"),
        Time.zone.local(2027, 4, 5, 19, 30, 0).iso8601
      ].join("::"),
      source_snapshot: {
        "sources" => [
          {
            "source" => "eventim",
            "external_event_id" => "old-eventim-id",
            "source_identifier" => "old-eventim-id:2027-04-05",
            "start_at" => Time.zone.local(2027, 4, 5, 19, 30, 0).iso8601
          }
        ]
      }
    )
    stale_event.event_offers.create!(
      source: "eventim",
      source_event_id: "old-eventim-id",
      ticket_url: "https://example.com/old-event",
      sold_out: false,
      priority_rank: 10
    )

    exact_event = Event.create!(
      artist_name: "This is THE GREATEST SHOW!",
      title: "Die größten Musical Hits aller Zeiten - Tour 2027",
      start_at: target_start_at,
      venue: "Stage Apollo Theater Stuttgart",
      city: "Stuttgart",
      status: "published",
      primary_source: "eventim",
      source_fingerprint: target_fingerprint
    )

    RawEventImport.create!(
      import_source: source,
      import_event_type: "eventim",
      source_identifier: "new-eventim-id:2027-04-26",
      payload: {
        "eventid" => "new-eventim-id",
        "eventdate" => "2027-04-26",
        "eventtime" => "19:30",
        "eventplace" => "Stuttgart",
        "eventvenue" => "Stage Apollo Theater Stuttgart",
        "eventname" => "This is THE GREATEST SHOW! - Die größten Musical Hits aller Zeiten - Tour 2027",
        "artistname" => "This is THE GREATEST SHOW!",
        "eventlink" => "https://example.com/new-event",
        "espicture_big" => "https://example.com/new-event.jpg"
      }
    )

    match_strategy_class = Merging::SyncFromImports::MatchStrategy
    match_strategy_class.alias_method :__original_call_for_test, :call
    match_strategy_class.define_method(:call) do |records:|
      Merging::SyncFromImports::MatchStrategy::Result.new(event: stale_event, reason: "source_snapshot", score: 1.0)
    end

    assert_nothing_raised do
      Merging::SyncFromImports.new.call
    end

    assert_equal target_fingerprint, exact_event.reload.source_fingerprint
    assert_equal target_start_at, exact_event.start_at
    assert_includes exact_event.source_snapshot.fetch("sources").map { |entry| entry.fetch("external_event_id") }, "new-eventim-id"

    assert_equal Time.zone.local(2027, 4, 5, 19, 30, 0), stale_event.reload.start_at
    assert_equal "old-eventim-id", stale_event.event_offers.order(:id).last.source_event_id
  ensure
    match_strategy_class.alias_method :call, :__original_call_for_test
    match_strategy_class.remove_method :__original_call_for_test
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

  test "assigns imported event series from explicit provider metadata" do
    source_eventim = import_sources(:two)

    RawEventImport.create!(
      import_source: source_eventim,
      import_event_type: "eventim",
      source_identifier: "series-a:2026-12-20",
      payload: {
        "eventid" => "series-a",
        "eventdate" => "2026-12-20",
        "eventplace" => "Stuttgart",
        "eventvenue" => "Im Wizemann",
        "eventname" => "Frida Night I",
        "artist" => { "artistname" => "Viva la Vida" },
        "esid" => "eventim-series-42",
        "esname" => "Viva la Vida"
      }
    )
    RawEventImport.create!(
      import_source: source_eventim,
      import_event_type: "eventim",
      source_identifier: "series-b:2026-12-21",
      payload: {
        "eventid" => "series-b",
        "eventdate" => "2026-12-21",
        "eventplace" => "Stuttgart",
        "eventvenue" => "Im Wizemann",
        "eventname" => "Frida Night II",
        "artist" => { "artistname" => "Viva la Vida" },
        "esid" => "eventim-series-42",
        "esname" => "Viva la Vida"
      }
    )

    Merging::SyncFromImports.new.call

    first_event = Event.find_by!(artist_name: "Viva la Vida", start_at: Time.zone.local(2026, 12, 20, 0, 0, 0))
    second_event = Event.find_by!(artist_name: "Viva la Vida", start_at: Time.zone.local(2026, 12, 21, 0, 0, 0))

    assert first_event.event_series.imported?
    assert_equal first_event.event_series_id, second_event.event_series_id
    assert_equal "eventim-series-42", first_event.event_series.source_key
    assert_equal "eventim-series-42", first_event.source_snapshot.dig("sources", 0, "event_series", "source_key")
  end

  test "keeps manual event series overrides on later merges" do
    source_eventim = import_sources(:two)
    source_identifier = "manual-series-keep:2026-12-24"

    RawEventImport.create!(
      import_source: source_eventim,
      import_event_type: "eventim",
      source_identifier: source_identifier,
      payload: {
        "eventid" => "manual-series-keep",
        "eventdate" => "2026-12-24",
        "eventplace" => "Stuttgart",
        "eventvenue" => "Im Wizemann",
        "eventname" => "Frida Night",
        "artist" => { "artistname" => "Viva la Vida" },
        "esid" => "eventim-series-imported",
        "esname" => "Imported Reihe"
      }
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Viva la Vida", start_at: Time.zone.local(2026, 12, 24, 0, 0, 0))
    manual_series = EventSeries.create!(origin: "manual", name: "Manuelle Reihe")
    event.update!(event_series: manual_series, event_series_assignment: "manual")

    RawEventImport.create!(
      import_source: source_eventim,
      import_event_type: "eventim",
      source_identifier: source_identifier,
      payload: {
        "eventid" => "manual-series-keep",
        "eventdate" => "2026-12-24",
        "eventplace" => "Stuttgart",
        "eventvenue" => "Im Wizemann",
        "eventname" => "Frida Night Update",
        "artist" => { "artistname" => "Viva la Vida" },
        "esid" => "eventim-series-imported",
        "esname" => "Imported Reihe"
      }
    )

    Merging::SyncFromImports.new.call

    assert_equal manual_series.id, event.reload.event_series_id
    assert_equal "manual", event.event_series_assignment
  end

  test "does not reassign event series after an editor manually removed the event from a series" do
    source_eventim = import_sources(:two)
    source_identifier = "manual-series-none:2026-12-25"

    RawEventImport.create!(
      import_source: source_eventim,
      import_event_type: "eventim",
      source_identifier: source_identifier,
      payload: {
        "eventid" => "manual-series-none",
        "eventdate" => "2026-12-25",
        "eventplace" => "Stuttgart",
        "eventvenue" => "Im Wizemann",
        "eventname" => "Frida Night",
        "artist" => { "artistname" => "Viva la Vida" },
        "esid" => "eventim-series-none",
        "esname" => "Imported Reihe"
      }
    )

    Merging::SyncFromImports.new.call

    event = Event.find_by!(artist_name: "Viva la Vida", start_at: Time.zone.local(2026, 12, 25, 0, 0, 0))
    event.update!(event_series: nil, event_series_assignment: "manual_none")

    RawEventImport.create!(
      import_source: source_eventim,
      import_event_type: "eventim",
      source_identifier: source_identifier,
      payload: {
        "eventid" => "manual-series-none",
        "eventdate" => "2026-12-25",
        "eventplace" => "Stuttgart",
        "eventvenue" => "Im Wizemann",
        "eventname" => "Frida Night Update",
        "artist" => { "artistname" => "Viva la Vida" },
        "esid" => "eventim-series-none",
        "esname" => "Imported Reihe"
      }
    )

    Merging::SyncFromImports.new.call

    assert_nil event.reload.event_series_id
    assert_equal "manual_none", event.event_series_assignment
  end
end
