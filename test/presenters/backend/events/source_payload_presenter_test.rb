require "test_helper"

class Backend::Events::SourcePayloadPresenterTest < ActiveSupport::TestCase
  test "extracts payload sources from source snapshot" do
    event = Event.new(
      source_snapshot: {
        "sources" => [
          {
            "source" => "eventim",
            "external_event_id" => "evt-1",
            "raw_payload" => {
              "dump_payload" => { "eventid" => "evt-1", "promoterid" => "36" },
              "detail_payload" => { "foo" => "bar" }
            }
          }
        ]
      }
    )

    presenter = Backend::Events::SourcePayloadPresenter.new(event)
    payload_source = presenter.payload_sources.first

    assert_equal 1, presenter.payload_sources.size
    assert_equal "eventim", payload_source.source
    assert_equal "evt-1", payload_source.external_event_id
    assert_includes payload_source.formatted_dump_payload, "\"promoterid\": \"36\""
  end

  test "uses eventim payload projection to derive promoter id" do
    event = Event.new(
      promoter_id: "",
      source_snapshot: {
        "sources" => [
          {
            "source" => "eventim",
            "external_event_id" => "evt-1",
            "raw_payload" => {
              "dump_payload" => {
                "eventid" => "evt-1",
                "eventdate" => "2026-06-17",
                "eventvenue" => "Im Wizemann",
                "eventname" => "Band Eventim",
                "sideArtistNames" => "Band Eventim",
                "promoterid" => "36"
              },
              "detail_payload" => {}
            }
          }
        ]
      }
    )

    presenter = Backend::Events::SourcePayloadPresenter.new(event)

    assert_equal "36", presenter.display_promoter_id
  end

  test "prefers direct event promoter id" do
    event = Event.new(promoter_id: "10135", source_snapshot: {})

    presenter = Backend::Events::SourcePayloadPresenter.new(event)

    assert_equal "10135", presenter.display_promoter_id
  end
end
