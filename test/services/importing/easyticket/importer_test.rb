require "test_helper"
require "digest"

module Importing
  module Easyticket
    class ImporterTest < ActiveSupport::TestCase
      class StubDumpFetcher
        def initialize(events)
          @events = events
        end

        def fetch_events
          @events
        end
      end

      class StubDetailFetcher
        def initialize(payload_by_event_id)
          @payload_by_event_id = payload_by_event_id
        end

        def fetch(event_id)
          @payload_by_event_id.fetch(event_id.to_s, {})
        end
      end

      setup do
        @source = import_sources(:one)
      end

      test "imports matching events and tracks run metrics" do
        dump_events = [
          {
            "event_id" => "999",
            "date" => "2026-06-17",
            "title" => "Band A Live",
            "sub1" => "Band A",
            "loc_city" => "Stuttgart",
            "loc_name" => "Im Wizemann"
          },
          {
            "event_id" => "1000",
            "date" => "2026-06-18",
            "title" => "Should Be Filtered",
            "sub1" => "Filtered",
            "loc_city" => "Berlin",
            "loc_name" => "Tempodrom"
          }
        ]

        detail_payloads = {
          "999" => {
            "data" => {
              "event" => { "artist" => "Band A" },
              "images" => [
                {
                  "paths" => [
                    { "type" => "large", "url" => "https://img.example/999-large.jpg" }
                  ]
                }
              ]
            }
          }
        }

        run = Importer.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new(dump_events),
          detail_fetcher: StubDetailFetcher.new(detail_payloads)
        ).call

        imported = EasyticketImportEvent.find_by!(
          import_source: @source,
          external_event_id: "999",
          concert_date: Date.new(2026, 6, 17)
        )

        assert_equal "succeeded", run.status
        assert_equal 2, run.fetched_count
        assert_equal 1, run.filtered_count
        assert_equal 1, run.imported_count
        assert_equal 1, run.upserted_count
        assert_equal 0, run.failed_count
        assert_includes run.metadata.fetch("filtered_out_cities", []), "Berlin"

        assert_equal "Band A", imported.artist_name
        assert_equal "17.6.2026", imported.concert_date_label
        assert_equal "Stuttgart, Im Wizemann", imported.venue_label
        assert_equal "Band A", imported.detail_payload.dig("data", "event", "artist")
        assert imported.is_active
        assert_equal [ "https://img.example/999-large.jpg" ], imported.import_event_images.ordered.pluck(:image_url)
      end

      test "deactivates stale events not seen in current run" do
        stale_event = EasyticketImportEvent.create!(
          import_source: @source,
          external_event_id: "stale-1",
          concert_date: Date.new(2026, 7, 1),
          city: "Stuttgart",
          venue_name: "Im Wizemann",
          title: "Old Event",
          artist_name: "Old Artist",
          concert_date_label: "1.7.2026",
          venue_label: "Stuttgart, Im Wizemann",
          dump_payload: { "event_id" => "stale-1" },
          detail_payload: {},
          is_active: true,
          first_seen_at: 2.days.ago,
          last_seen_at: 2.days.ago,
          source_payload_hash: "hash-stale"
        )

        run = Importer.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new(
            [
              {
                "event_id" => "fresh-1",
                "date" => "2026-07-02",
                "title" => "Fresh Event",
                "sub1" => "Fresh Artist",
                "loc_city" => "Stuttgart",
                "loc_name" => "Im Wizemann"
              }
            ]
          ),
          detail_fetcher: StubDetailFetcher.new("fresh-1" => { "data" => {} })
        ).call

        assert_equal 1, run.imported_count
        assert_equal 1, run.upserted_count
        assert_not stale_event.reload.is_active
      end

      test "does not start a second run while one is already active" do
        active_run = @source.import_runs.create!(
          status: "running",
          source_type: "easyticket",
          started_at: 5.minutes.ago
        )

        dump_fetcher =
          Class.new do
            def fetch_events
              raise "must not fetch while another run is active"
            end
          end.new

        run = Importer.new(
          import_source: @source,
          dump_fetcher: dump_fetcher,
          detail_fetcher: StubDetailFetcher.new({})
        ).call

        assert_equal active_run.id, run.id
        assert_equal "running", run.reload.status
      end

      test "auto-fails stale running runs before starting a new one" do
        stale_run = @source.import_runs.create!(
          status: "running",
          source_type: "easyticket",
          started_at: (Importer::RUN_STALE_AFTER + 5.minutes).ago
        )

        run = Importer.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new([]),
          detail_fetcher: StubDetailFetcher.new({})
        ).call

        assert_equal "failed", stale_run.reload.status
        assert_equal "succeeded", run.status
      end

      test "marks run as canceled when stop is requested" do
        dump_events = [
          {
            "event_id" => "cancel-1",
            "date" => "2026-08-10",
            "title" => "Cancelable Event 1",
            "sub1" => "Artist 1",
            "loc_city" => "Stuttgart",
            "loc_name" => "Im Wizemann"
          },
          {
            "event_id" => "cancel-2",
            "date" => "2026-08-11",
            "title" => "Cancelable Event 2",
            "sub1" => "Artist 2",
            "loc_city" => "Stuttgart",
            "loc_name" => "Im Wizemann"
          }
        ]

        detail_fetcher =
          Class.new do
            def initialize(source)
              @source = source
              @called = false
            end

            def fetch(_event_id)
              unless @called
                @called = true
                run = @source.import_runs.where(status: "running").order(started_at: :desc).first
                run.update!(metadata: run.metadata.merge("stop_requested" => true))
              end

              { "data" => {} }
            end
          end.new(@source)

        run = Importer.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new(dump_events),
          detail_fetcher: detail_fetcher
        ).call

        assert_equal "canceled", run.status
        assert_equal 2, run.fetched_count
        assert_equal 1, run.filtered_count
        assert_equal 1, run.imported_count
        assert_equal 1, run.upserted_count
      end

      test "does not fetch detail payload when dump payload is unchanged" do
        dump_payload = {
          "event_id" => "same-1",
          "date" => "2026-09-10",
          "title" => "Same Event",
          "sub1" => "Same Artist",
          "loc_city" => "Stuttgart",
          "loc_name" => "Im Wizemann"
        }
        payload_hash = Digest::SHA256.hexdigest(dump_payload.to_json)

        existing_event = EasyticketImportEvent.create!(
          import_source: @source,
          external_event_id: "same-1",
          concert_date: Date.new(2026, 9, 10),
          city: "Stuttgart",
          venue_name: "Im Wizemann",
          title: "Same Event",
          artist_name: "Same Artist",
          concert_date_label: "10.9.2026",
          venue_label: "Stuttgart, Im Wizemann",
          dump_payload: dump_payload,
          detail_payload: { "data" => { "event" => { "title" => "Same Event" } } },
          is_active: false,
          first_seen_at: 2.days.ago,
          last_seen_at: 2.days.ago,
          source_payload_hash: payload_hash
        )

        detail_fetcher =
          Class.new do
            def fetch(_event_id)
              raise "detail api must not be called for unchanged dump payload"
            end
          end.new

        run = Importer.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new([ dump_payload ]),
          detail_fetcher: detail_fetcher
        ).call

        assert_equal "succeeded", run.status
        assert_equal 1, run.filtered_count
        assert_equal 1, run.imported_count
        assert_equal 0, run.upserted_count
        assert_equal 0, run.failed_count
        assert existing_event.reload.is_active
        assert_empty existing_event.import_event_images
      end

      test "syncs images from stored detail payload when dump payload is unchanged" do
        dump_payload = {
          "event_id" => "same-2",
          "date" => "2026-09-11",
          "title" => "Same Event Two",
          "sub1" => "Same Artist Two",
          "loc_city" => "Stuttgart",
          "loc_name" => "Im Wizemann"
        }
        payload_hash = Digest::SHA256.hexdigest(dump_payload.to_json)

        existing_event = EasyticketImportEvent.create!(
          import_source: @source,
          external_event_id: "same-2",
          concert_date: Date.new(2026, 9, 11),
          city: "Stuttgart",
          venue_name: "Im Wizemann",
          title: "Same Event Two",
          artist_name: "Same Artist Two",
          concert_date_label: "11.9.2026",
          venue_label: "Stuttgart, Im Wizemann",
          dump_payload: dump_payload,
          detail_payload: {
            "data" => {
              "images" => [
                {
                  "paths" => [
                    { "type" => "large", "url" => "https://img.example/same-2-large.jpg" }
                  ]
                }
              ]
            }
          },
          is_active: true,
          first_seen_at: 2.days.ago,
          last_seen_at: 2.days.ago,
          source_payload_hash: payload_hash
        )

        detail_fetcher =
          Class.new do
            def fetch(_event_id)
              raise "detail api must not be called for unchanged dump payload"
            end
          end.new

        run = Importer.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new([ dump_payload ]),
          detail_fetcher: detail_fetcher
        ).call

        assert_equal "succeeded", run.status
        assert_equal 0, run.upserted_count
        assert_equal [ "https://img.example/same-2-large.jpg" ], existing_event.reload.import_event_images.ordered.pluck(:image_url)
      end

      test "stores import_run_error when event processing fails" do
        dump_events = [
          {
            "event_id" => "err-1",
            "date" => "2026-10-10",
            "title" => "Broken Event",
            "sub1" => "Broken Artist",
            "loc_city" => "Stuttgart",
            "loc_name" => "Im Wizemann"
          }
        ]

        detail_fetcher =
          Class.new do
            def fetch(_event_id)
              raise Net::ReadTimeout, "detail timeout"
            end
          end.new

        run = Importer.new(
          import_source: @source,
          dump_fetcher: StubDumpFetcher.new(dump_events),
          detail_fetcher: detail_fetcher
        ).call

        assert_equal "succeeded", run.status
        assert_equal 1, run.failed_count
        assert_equal 1, run.import_run_errors.count

        error = run.import_run_errors.order(:created_at).last
        assert_equal "easyticket", error.source_type
        assert_equal "err-1", error.external_event_id
        assert_equal "Net::ReadTimeout", error.error_class
        assert_includes error.message, "detail timeout"
        assert_equal "err-1", error.payload["event_id"]
      end

      test "stores import_run_error when run fails" do
        failing_dump_fetcher =
          Class.new do
            def fetch_events
              raise "dump download failed"
            end
          end.new

        assert_raises RuntimeError do
          Importer.new(
            import_source: @source,
            dump_fetcher: failing_dump_fetcher,
            detail_fetcher: StubDetailFetcher.new({})
          ).call
        end

        run = @source.import_runs.where(source_type: "easyticket").order(:created_at).last
        assert_equal "failed", run.status
        assert_equal 1, run.import_run_errors.count

        error = run.import_run_errors.order(:created_at).last
        assert_equal "RuntimeError", error.error_class
        assert_includes error.message, "dump download failed"
      end
    end
  end
end
