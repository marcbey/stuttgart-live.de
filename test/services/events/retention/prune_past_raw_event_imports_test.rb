require "test_helper"

class Events::Retention::PrunePastRawEventImportsTest < ActiveSupport::TestCase
  setup do
    @now = Time.zone.parse("2026-04-15 10:00:00")
  end

  test "deletes raw imports for past events and keeps future or unparseable ones" do
    stale_raw_import = RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "stale-easyticket:2026-03-10",
      payload: {
        "event_id" => "stale-easyticket",
        "date" => "2026-03-10",
        "title_1" => "Stale Artist",
        "title_2" => "Stale Event",
        "loc_name" => "Im Wizemann",
        "loc_city" => "Stuttgart"
      },
      detail_payload: {}
    )
    future_raw_import = RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "future-easyticket:2026-05-20",
      payload: {
        "event_id" => "future-easyticket",
        "date" => "2026-05-20",
        "title_1" => "Future Artist",
        "title_2" => "Future Event",
        "loc_name" => "LKA Longhorn",
        "loc_city" => "Stuttgart"
      },
      detail_payload: {}
    )
    unparseable_raw_import = RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "broken-easyticket:invalid",
      payload: {
        "event_id" => "broken-easyticket",
        "date" => "not-a-date",
        "title_1" => "Broken Artist",
        "title_2" => "Broken Event"
      },
      detail_payload: {}
    )

    result = travel_to(@now) do
      Events::Retention::PrunePastRawEventImports.call(
        scope: RawEventImport.where(id: [ stale_raw_import.id, future_raw_import.id, unparseable_raw_import.id ])
      )
    end

    assert_not RawEventImport.exists?(stale_raw_import.id)
    assert RawEventImport.exists?(future_raw_import.id)
    assert RawEventImport.exists?(unparseable_raw_import.id)
    assert_equal 1, result.deleted_count
    assert_equal({ "easyticket" => 1 }, result.deleted_by_source)
    assert_equal 1, result.skipped_count
    assert_equal Time.zone.parse("2026-03-15 00:00:00"), result.cutoff_at
  end

  test "skips raw imports when record building raises" do
    raw_import = RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "raising-easyticket:2026-03-10",
      payload: {
        "event_id" => "raising-easyticket",
        "date" => "2026-03-10"
      },
      detail_payload: {}
    )
    failing_record_builder = Object.new
    failing_record_builder.define_singleton_method(:build_record) do |_raw_event_import|
      raise "kaputt"
    end

    result = travel_to(@now) do
      Events::Retention::PrunePastRawEventImports.call(
        scope: RawEventImport.where(id: raw_import.id),
        record_builder: failing_record_builder
      )
    end

    assert RawEventImport.exists?(raw_import.id)
    assert_equal 0, result.deleted_count
    assert_equal({}, result.deleted_by_source)
    assert_equal 1, result.skipped_count
  end
end
