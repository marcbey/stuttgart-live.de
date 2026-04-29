require "test_helper"

module Importing
  module Easyticket
    class ImporterTest < ActiveSupport::TestCase
    class StubDumpFetcher
      def initialize(events)
        @events = events
      end

      def fetch_events(heartbeat: nil, stop_requested: nil)
        @events
      end
    end

    class StubDetailFetcher
      attr_reader :calls

      def initialize(payload_by_event_id)
        @payload_by_event_id = payload_by_event_id
        @calls = []
      end

      def fetch(event_id, heartbeat: nil, stop_requested: nil)
        @calls << event_id
        @payload_by_event_id.fetch(event_id.to_s, {})
      end
    end

      setup do
        @source = import_sources(:one)
      end

      test "imports matching events into raw_event_imports and tracks run metrics" do
        dump_events = [
          {
            "event_id" => "999",
            "date_time" => "2026-06-17 20:00:00",
            "location_name" => "Im Wizemann Stuttgart",
            "title_1" => "Band A Live",
            "title_2" => "Band A",
            "organizer_id" => "382",
            "data" => {
              "location" => {
                "name" => "Im Wizemann",
                "city" => "Stuttgart"
              },
              "images" => {
                "999" => {
                  "large" => "https://img.example/999-large.jpg"
                }
              }
            }
          },
          {
            "event_id" => "1000",
            "date_time" => "2026-06-18 21:00:00",
            "location_name" => "Tempodrom Berlin",
            "title_1" => "Should Be Filtered"
          }
        ]

        run = Importer.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new(dump_events),
          detail_fetcher: StubDetailFetcher.new({})
        ).call

        imported = RawEventImport.find_by!(
          import_source: @source,
          import_event_type: "easyticket",
          source_identifier: "999:2026-06-17"
        )

        assert_equal "succeeded", run.status
        assert_equal 2, run.fetched_count
        assert_equal 1, run.filtered_count
        assert_equal 1, run.imported_count
        assert_equal 1, run.upserted_count
        assert_equal 0, run.failed_count
        assert_includes run.metadata.fetch("filtered_out_cities", []), "Tempodrom Berlin"
        assert_equal "999", imported.payload["event_id"]
        assert_equal "Band A", imported.payload["title_2"]
        assert_equal({}, imported.detail_payload)
      end

      test "does not start a second run while one is already active" do
        active_run = @source.import_runs.create!(
          status: "running",
          source_type: "easyticket",
          started_at: 5.minutes.ago
        )

        run = Importer.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new([]),
          detail_fetcher: StubDetailFetcher.new({})
        ).call

        assert_equal active_run.id, run.id
        assert_equal "running", run.reload.status
      end

      test "marks run as canceled when stop is requested" do
        dump_events = [
          {
            "event_id" => "cancel-1",
            "date" => "2026-08-10",
            "title" => "Cancelable Event 1",
            "loc_city" => "Stuttgart",
            "loc_name" => "Im Wizemann"
          },
          {
            "event_id" => "cancel-2",
            "date" => "2026-08-11",
            "title" => "Cancelable Event 2",
            "loc_city" => "Stuttgart",
            "loc_name" => "Im Wizemann"
          }
        ]

        canceling_importer_class =
          Class.new(Importer) do
            private

            def normalize_payload(payload)
              @normalize_payload_calls ||= 0
              @normalize_payload_calls += 1

              if @normalize_payload_calls == 1
                run = import_source.import_runs.where(status: "running").order(started_at: :desc).first
                run.update!(metadata: run.metadata.merge("stop_requested" => true))
              end

              super
            end
          end

        run = canceling_importer_class.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new(dump_events),
          detail_fetcher: StubDetailFetcher.new({})
        ).call

        assert_equal "canceled", run.status
        assert_equal 2, run.fetched_count
        assert_equal 1, run.filtered_count
        assert_equal 1, run.imported_count
        assert_equal 1, run.upserted_count
      end

      test "fetches detail payload only when payload has no image candidates" do
        dump_events = [
          {
            "event_id" => "no-image-1",
            "date_time" => "2026-06-17 20:00:00",
            "location_name" => "Im Wizemann Stuttgart",
            "title_1" => "Band A Live",
            "title_2" => "Band A"
          },
          {
            "event_id" => "has-image-2",
            "date_time" => "2026-06-18 20:00:00",
            "location_name" => "Im Wizemann Stuttgart",
            "title_1" => "Band B Live",
            "title_2" => "Band B",
            "data" => {
              "images" => {
                "has-image-2" => {
                  "large" => "https://img.example/has-image-2-large.jpg"
                }
              }
            }
          }
        ]

        detail_fetcher = StubDetailFetcher.new(
          "no-image-1" => {
            "data" => {
              "images" => [
                {
                  "paths" => [
                    { "type" => "detail_path", "url" => "https://img.example/no-image-1-detail.jpg" }
                  ]
                }
              ]
            }
          }
        )

        Importer.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new(dump_events),
          detail_fetcher: detail_fetcher
        ).call

        without_image = RawEventImport.find_by!(source_identifier: "no-image-1:2026-06-17")
        with_image = RawEventImport.find_by!(source_identifier: "has-image-2:2026-06-18")

        assert_equal [ "no-image-1" ], detail_fetcher.calls
        assert_equal "https://img.example/no-image-1-detail.jpg",
          without_image.detail_payload.dig("data", "images", 0, "paths", 0, "url")
        assert_equal({}, with_image.detail_payload)
      end

      test "uses payload id for detail payload when title_3 is descriptive text" do
        dump_events = [
          {
            "id" => "105758",
            "event_id" => "104364",
            "title_3" => "The Beast Goes On",
            "date_time" => "2026-06-17 20:00:00",
            "location_name" => "Im Wizemann Stuttgart",
            "title_1" => "Band A Live"
          }
        ]
        detail_fetcher = StubDetailFetcher.new("105758" => {})

        Importer.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new(dump_events),
          detail_fetcher: detail_fetcher
        ).call

        assert_equal [ "105758" ], detail_fetcher.calls
      end

      test "cancels run when stop is requested during dump fetching" do
        canceling_dump_fetcher = Class.new do
          def fetch_events(heartbeat: nil, stop_requested: nil)
            heartbeat&.call
            raise Importing::StopRequested if stop_requested&.call
          end
        end.new

        run = @source.import_runs.create!(
          status: "running",
          source_type: "easyticket",
          started_at: 1.minute.ago,
          metadata: {
            "execution_started_at" => 1.minute.ago.iso8601,
            "stop_requested" => true,
            "stop_requested_at" => 30.seconds.ago.iso8601
          }
        )

        result = Importer.new(
          import_source: @source,
          dump_fetcher: canceling_dump_fetcher,
          detail_fetcher: StubDetailFetcher.new({}),
          preexisting_run_id: run.id
        ).call

        assert_equal "canceled", result.reload.status
        assert result.finished_at.present?
      end
    end
  end
end
