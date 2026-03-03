require "test_helper"

module Importing
  module Eventim
    class ImporterTest < ActiveSupport::TestCase
      class StubFeedFetcher
        def initialize(events)
          @events = events
        end

        def fetch_events
          @events
        end
      end

      setup do
        @source = import_sources(:two)
      end

      test "imports matching events and tracks run metrics" do
        feed_events = [
          {
            "eventid" => "evt-900",
            "eventdate" => "2026-06-17",
            "eventplace" => "Stuttgart",
            "eventvenue" => "Im Wizemann",
            "eventname" => "Band Eventim",
            "sideArtistNames" => "Band Eventim",
            "eventlink" => "https://tickets.example/evt-900"
          },
          {
            "eventid" => "evt-901",
            "eventdate" => "2026-06-18",
            "eventplace" => "Berlin",
            "eventvenue" => "Tempodrom",
            "eventname" => "Filtered Out",
            "sideArtistNames" => "Filtered Out",
            "eventlink" => "https://tickets.example/evt-901"
          }
        ]

        run = Importer.new(
          import_source: @source,
          feed_fetcher: StubFeedFetcher.new(feed_events)
        ).call

        imported = EventimImportEvent.find_by!(
          import_source: @source,
          external_event_id: "evt-900",
          concert_date: Date.new(2026, 6, 17)
        )

        assert_equal "succeeded", run.status
        assert_equal 2, run.fetched_count
        assert_equal 1, run.filtered_count
        assert_equal 1, run.imported_count
        assert_equal 1, run.upserted_count
        assert_equal 0, run.failed_count
        assert_includes run.metadata.fetch("filtered_out_cities", []), "Berlin"

        assert_equal "Band Eventim", imported.artist_name
        assert_equal "17.6.2026", imported.concert_date_label
        assert_equal "Stuttgart, Im Wizemann", imported.venue_label
        assert imported.is_active
      end

      test "does not start a second run while one is already active" do
        active_run = @source.import_runs.create!(
          status: "running",
          source_type: "eventim",
          started_at: 5.minutes.ago
        )

        feed_fetcher =
          Class.new do
            def fetch_events
              raise "must not fetch while another run is active"
            end
          end.new

        run = Importer.new(
          import_source: @source,
          feed_fetcher: feed_fetcher
        ).call

        assert_equal active_run.id, run.id
        assert_equal "running", run.reload.status
      end

      test "auto-fails heartbeat-stale running runs before starting a new one" do
        stale_run = @source.import_runs.create!(
          status: "running",
          source_type: "eventim",
          started_at: 10.minutes.ago
        )
        stale_run.update_columns(updated_at: (Importer::RUN_HEARTBEAT_STALE_AFTER + 1.minute).ago)

        run = Importer.new(
          import_source: @source,
          feed_fetcher: StubFeedFetcher.new([])
        ).call

        assert_equal "failed", stale_run.reload.status
        assert_equal "succeeded", run.status
      end

      test "does not upsert unchanged payload twice" do
        feed_payload = {
          "eventid" => "evt-same",
          "eventdate" => "2026-09-10",
          "eventplace" => "Stuttgart",
          "eventvenue" => "Im Wizemann",
          "eventname" => "Same Eventim Event",
          "sideArtistNames" => "Same Eventim Artist",
          "eventlink" => "https://tickets.example/evt-same"
        }
        attributes = PayloadProjection.new(feed_payload: feed_payload).to_attributes

        existing_event = EventimImportEvent.create!(
          import_source: @source,
          external_event_id: attributes[:external_event_id],
          concert_date: attributes[:concert_date],
          city: attributes[:city],
          venue_name: attributes[:venue_name],
          title: attributes[:title],
          artist_name: attributes[:artist_name],
          concert_date_label: attributes[:concert_date_label],
          venue_label: attributes[:venue_label],
          dump_payload: feed_payload,
          detail_payload: {},
          is_active: false,
          first_seen_at: 2.days.ago,
          last_seen_at: 2.days.ago,
          source_payload_hash: attributes[:source_payload_hash]
        )

        run = Importer.new(
          import_source: @source,
          feed_fetcher: StubFeedFetcher.new([ feed_payload ])
        ).call

        assert_equal "succeeded", run.status
        assert_equal 1, run.filtered_count
        assert_equal 1, run.imported_count
        assert_equal 0, run.upserted_count
        assert existing_event.reload.is_active
      end

      test "stores import_run_error when event processing fails" do
        feed_payload = {
          "eventid" => "evt-error-1",
          "eventdate" => "2026-11-11",
          "eventplace" => "Stuttgart",
          "eventvenue" => "Im Wizemann",
          "eventname" => "Broken Eventim Event",
          "sideArtistNames" => "Broken Artist",
          "eventlink" => "https://tickets.example/evt-error-1"
        }

        failing_importer_class =
          Class.new(Importer) do
            private

            def upsert_import_event!(**)
              raise RuntimeError, "cannot persist feed row"
            end
          end

        run = failing_importer_class.new(
          import_source: @source,
          feed_fetcher: StubFeedFetcher.new([ feed_payload ])
        ).call

        assert_equal "succeeded", run.status
        assert_equal 1, run.failed_count
        assert_equal 1, run.import_run_errors.count

        error = run.import_run_errors.order(:created_at).last
        assert_equal "eventim", error.source_type
        assert_equal "evt-error-1", error.external_event_id
        assert_equal "RuntimeError", error.error_class
        assert_includes error.message, "cannot persist feed row"
        assert_equal "evt-error-1", error.payload["eventid"]
      end

      test "stores import_run_error when run fails" do
        failing_feed_fetcher =
          Class.new do
            def fetch_events
              raise "feed download failed"
            end
          end.new

        assert_raises RuntimeError do
          Importer.new(
            import_source: @source,
            feed_fetcher: failing_feed_fetcher
          ).call
        end

        run = @source.import_runs.where(source_type: "eventim").order(:created_at).last
        assert_equal "failed", run.status
        assert_equal 1, run.import_run_errors.count

        error = run.import_run_errors.order(:created_at).last
        assert_equal "RuntimeError", error.error_class
        assert_includes error.message, "feed download failed"
      end
    end
  end
end
