require "test_helper"

class EditorialVenueImportTest < ActionDispatch::IntegrationTest
  setup do
    RawEventImport.delete_all
    sign_in_as(users(:one))
    @raw_import = RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "editorial-venue:2026-12-20",
      payload: {
        "event_id" => "editorial-venue",
        "date_time" => "2026-12-20 20:00:00",
        "loc_city" => "Stuttgart",
        "loc_name" => "LKA Longhorn",
        "title_1" => "Venue Regression Band",
        "title_2" => "Venue Regression Concert",
        "price_start" => 40
      }
    )
    Merging::SyncFromImports.new.call
    @event = Event.find_by!(artist_name: "Venue Regression Band")
  end

  test "keeps a selected editorial venue across repeated imports while updating prices" do
    venue = venues(:im_wizemann)
    patch backend_event_url(@event), params: { event: { venue_id: venue.id, venue_name: venue.name } }
    assert_response :redirect
    assert_equal venue, @event.reload.venue_record

    patch backend_event_url(@event), params: { event: { title: "Edited concert", venue_id: venue.id, venue_name: venue.name } }
    assert_response :redirect

    @raw_import.update!(payload: @raw_import.payload.merge("price_start" => 45))
    2.times { Merging::SyncFromImports.new.call }

    assert_equal venue, @event.reload.venue_record
    assert_equal BigDecimal("45"), @event.min_price
    assert_equal "LKA Longhorn", @event.source_snapshot.fetch("sources").first.fetch("venue")
    assert_equal 1, Event.where(artist_name: "Venue Regression Band").count
  end

  test "keeps a new venue entered as free text across imports" do
    patch backend_event_url(@event), params: { event: { venue_id: "", venue_name: "Neue Konzerthalle" } }
    assert_response :redirect
    venue = @event.reload.venue_record
    assert_equal "Neue Konzerthalle", venue.name

    Merging::SyncFromImports.new.call

    assert_equal venue, @event.reload.venue_record
  end

  test "saving an unchanged venue still permits later provider venue changes" do
    venue = @event.venue_record
    patch backend_event_url(@event), params: { event: { venue_id: venue.id, venue_name: venue.name, title: "Edited concert" } }
    assert_response :redirect

    @raw_import.update!(payload: @raw_import.payload.merge("loc_name" => "Im Wizemann"))
    Merging::SyncFromImports.new.call

    assert_equal venues(:im_wizemann), @event.reload.venue_record
    assert_equal "Edited concert", @event.title
  end

  test "an invalid editorial change does not protect the venue from provider updates" do
    patch backend_event_url(@event), params: { event: { venue_name: "Im Wizemann", artist_name: "", title: "" } }
    assert_response :unprocessable_entity
    assert_equal venues(:lka_longhorn), @event.reload.venue_record

    @raw_import.update!(payload: @raw_import.payload.merge("loc_name" => "Neue Anbieterhalle"))
    Merging::SyncFromImports.new.call

    assert_equal "Neue Anbieterhalle", @event.reload.venue
  end
end
