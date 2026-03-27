require "test_helper"

class Backend::Events::SourcePayloadPresenterTest < ActiveSupport::TestCase
  test "extracts payload sources from source snapshot" do
    event = Event.new(
      source_snapshot: {
        "sources" => [
          {
            "source" => "eventim",
            "external_event_id" => "evt-1",
            "raw_payload" => { "eventid" => "evt-1", "promoterid" => "36" }
          }
        ]
      }
    )

    presenter = Backend::Events::SourcePayloadPresenter.new(event)
    payload_source = presenter.payload_sources.first

    assert_equal 1, presenter.payload_sources.size
    assert_equal "eventim", payload_source.source
    assert_equal "evt-1", payload_source.external_event_id
    assert_includes payload_source.formatted_payload, "\"promoterid\": \"36\""
  end

  test "prefers promoter name over promoter id" do
    event = Event.new(
      promoter_id: "36",
      promoter_name: "Reservix Veranstalter",
      source_snapshot: {
        "sources" => [
          {
            "source" => "eventim",
            "external_event_id" => "evt-1",
            "raw_payload" => {
              "eventid" => "evt-1",
              "eventdate" => "2026-06-17",
              "eventvenue" => "Im Wizemann",
              "eventname" => "Band Eventim",
              "artistname" => "Band Eventim",
              "promoterid" => "36"
            }
          }
        ]
      }
    )

    presenter = Backend::Events::SourcePayloadPresenter.new(event)

    assert_equal "Reservix Veranstalter", presenter.display_promoter
  end

  test "falls back to promoter id when no promoter name is present" do
    event = Event.new(promoter_id: "10135", source_snapshot: {})

    presenter = Backend::Events::SourcePayloadPresenter.new(event)

    assert_equal "10135", presenter.display_promoter
  end

  test "keeps payload sources available without raw event imports" do
    raw_import = RawEventImport.create!(
      import_source: import_sources(:one),
      import_event_type: "easyticket",
      source_identifier: "evt-2:2026-06-10",
      payload: { "event_id" => "evt-2", "title_2" => "Snapshot Event" },
      detail_payload: {}
    )
    event = Event.new(
      source_snapshot: {
        "sources" => [
          {
            "source" => "easyticket",
            "external_event_id" => "evt-2",
            "raw_payload" => { "event_id" => "evt-2", "title_2" => "Snapshot Event" }
          }
        ]
      }
    )

    presenter = Backend::Events::SourcePayloadPresenter.new(event)

    raw_import.destroy!

    assert_equal 1, presenter.payload_sources.size
    assert_includes presenter.payload_sources.first.formatted_payload, "\"title_2\": \"Snapshot Event\""
  end
end
