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

  test "deletes superseded raw imports older than retention while preserving latest and recent history" do
    old_snapshot = create_raw_import(
      source_identifier: "future-easyticket:2026-05-20",
      created_at: Time.zone.parse("2026-03-20 08:00:00")
    )
    recent_snapshot = create_raw_import(
      source_identifier: "future-easyticket:2026-05-20",
      created_at: Time.zone.parse("2026-04-10 08:00:00")
    )
    latest_snapshot = create_raw_import(
      source_identifier: "future-easyticket:2026-05-20",
      created_at: Time.zone.parse("2026-04-14 08:00:00")
    )
    old_without_newer_snapshot = create_raw_import(
      source_identifier: "single-future-easyticket:2026-05-20",
      created_at: Time.zone.parse("2026-03-20 08:00:00")
    )
    different_source_type_snapshot = create_raw_import(
      source: import_sources(:two),
      source_identifier: "future-easyticket:2026-05-20",
      created_at: Time.zone.parse("2026-03-20 08:00:00")
    )

    result = travel_to(@now) do
      Events::Retention::PrunePastRawEventImports.call(
        scope: RawEventImport.where(id: [
          old_snapshot.id,
          recent_snapshot.id,
          latest_snapshot.id,
          old_without_newer_snapshot.id,
          different_source_type_snapshot.id
        ]),
        superseded_delete_limit: 10
      )
    end

    assert_not RawEventImport.exists?(old_snapshot.id)
    assert RawEventImport.exists?(recent_snapshot.id)
    assert RawEventImport.exists?(latest_snapshot.id)
    assert RawEventImport.exists?(old_without_newer_snapshot.id)
    assert RawEventImport.exists?(different_source_type_snapshot.id)
    assert_equal 1, result.deleted_count
    assert_equal 1, result.deleted_superseded_count
    assert_equal 0, result.deleted_past_event_count
    assert_equal({ "easyticket" => 1 }, result.deleted_by_source)
    assert_equal Time.zone.parse("2026-04-01 10:00:00"), result.superseded_cutoff_at
    assert_not result.superseded_delete_limit_reached
  end

  test "limits superseded raw import deletion per run" do
    old_snapshots = 3.times.map do |index|
      source_identifier = "limited-future-#{index}:2026-05-20"
      old_snapshot = create_raw_import(
        source_identifier: source_identifier,
        created_at: Time.zone.parse("2026-03-20 08:00:00") + index.minutes
      )
      create_raw_import(
        source_identifier: source_identifier,
        created_at: Time.zone.parse("2026-04-14 08:00:00") + index.minutes
      )
      old_snapshot
    end

    result = travel_to(@now) do
      Events::Retention::PrunePastRawEventImports.call(
        scope: RawEventImport.where(source_identifier: old_snapshots.map(&:source_identifier)),
        batch_size: 1,
        superseded_delete_limit: 2
      )
    end

    assert_equal 2, result.deleted_count
    assert_equal 2, result.deleted_superseded_count
    assert_equal 0, result.deleted_past_event_count
    assert_equal 1, RawEventImport.where(id: old_snapshots.map(&:id)).count
    assert result.superseded_delete_limit_reached
  end

  private

  def create_raw_import(source: import_sources(:one), source_identifier:, created_at:)
    RawEventImport.create!(
      import_source: source,
      import_event_type: source.source_type,
      source_identifier: source_identifier,
      payload: {
        "event_id" => source_identifier.split(":").first,
        "date" => "2026-05-20",
        "title_1" => "Future Artist",
        "title_2" => "Future Event",
        "loc_name" => "LKA Longhorn",
        "loc_city" => "Stuttgart"
      },
      detail_payload: {},
      created_at: created_at,
      updated_at: created_at
    )
  end
end
