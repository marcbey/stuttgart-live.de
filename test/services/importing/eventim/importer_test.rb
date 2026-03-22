require "test_helper"

module Importing
  module Eventim
    class ImporterTest < ActiveSupport::TestCase
      class StubFeedFetcher
        def initialize(events)
          @events = events
        end

        def fetch_events(heartbeat: nil, stop_requested: nil)
          @events
        end
      end

      setup do
        @source = import_sources(:two)
      end

      test "imports matching feed rows into raw_event_imports and tracks run metrics" do
        feed_events = [
          {
            "eventid" => "evt-900",
            "eventdate" => "2026-06-17",
            "eventplace" => "Stuttgart",
            "eventvenue" => "Im Wizemann",
            "eventname" => "Band Eventim",
            "sideArtistNames" => "Band Eventim",
            "promoterid" => "36",
            "eventlink" => "https://tickets.example/evt-900"
          },
          {
            "eventid" => "evt-901",
            "eventdate" => "2026-06-18",
            "eventplace" => "Berlin",
            "eventvenue" => "Tempodrom",
            "eventname" => "Filtered Out"
          }
        ]

        run = Importer.new(
          import_source: @source,
          feed_fetcher: StubFeedFetcher.new(feed_events)
        ).call

        imported = RawEventImport.find_by!(
          import_source: @source,
          import_event_type: "eventim",
          source_identifier: "evt-900:2026-06-17"
        )

        assert_equal "succeeded", run.status
        assert_equal 2, run.fetched_count
        assert_equal 1, run.filtered_count
        assert_equal 1, run.imported_count
        assert_equal 1, run.upserted_count
        assert_equal 0, run.failed_count
        assert_includes run.metadata.fetch("filtered_out_cities", []), "Berlin"
        assert_equal "evt-900", imported.payload["eventid"]
      end

      test "does not start a second run while one is already active" do
        active_run = @source.import_runs.create!(
          status: "running",
          source_type: "eventim",
          started_at: 5.minutes.ago
        )

        run = Importer.new(
          import_source: @source,
          feed_fetcher: StubFeedFetcher.new([])
        ).call

        assert_equal active_run.id, run.id
        assert_equal "running", run.reload.status
      end

      test "stores import_run_error when raw row persistence fails" do
        feed_payload = {
          "eventid" => "evt-error-1",
          "eventdate" => "2026-11-11",
          "eventplace" => "Stuttgart",
          "eventvenue" => "Im Wizemann",
          "eventname" => "Broken Eventim Event"
        }

        failing_importer_class =
          Class.new(Importer) do
            private

            def source_identifier_for(_feed_payload, external_event_id:)
              raise RuntimeError, "cannot persist feed row for #{external_event_id}"
            end

            def normalize_payload(payload)
              super
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
        assert_includes error.message, "cannot persist feed row for evt-error-1"
      end

      test "cancels run when stop is requested during feed fetching" do
        stop_aware_fetcher = Class.new do
          def fetch_events(heartbeat: nil, stop_requested: nil)
            heartbeat&.call
            raise Importing::StopRequested if stop_requested&.call

            []
          end
        end.new

        run = @source.import_runs.create!(
          status: "running",
          source_type: "eventim",
          started_at: 1.minute.ago,
          metadata: {
            "execution_started_at" => 1.minute.ago.iso8601,
            "stop_requested" => true,
            "stop_requested_at" => 30.seconds.ago.iso8601
          }
        )

        result = Importer.new(
          import_source: @source,
          feed_fetcher: stop_aware_fetcher,
          preexisting_run_id: run.id
        ).call

        assert_equal run.id, result.id
        assert_equal "canceled", result.reload.status
        assert result.finished_at.present?
      end

      test "does not reload import run state for every feed row" do
        feed_events = 500.times.map do |index|
          {
            "eventid" => "evt-bench-#{index}",
            "eventdate" => "2026-06-17",
            "eventplace" => "Stuttgart",
            "eventvenue" => "Im Wizemann",
            "eventname" => "Band #{index}"
          }
        end

        import_run_selects = 0
        callback = lambda do |_name, _start, _finish, _id, payload|
          sql = payload[:sql].to_s
          next unless sql.start_with?("SELECT")
          next unless sql.include?(%("import_runs"))

          import_run_selects += 1
        end

        run = nil
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
          run = Importer.new(
            import_source: @source,
            feed_fetcher: StubFeedFetcher.new(feed_events)
          ).call
        end

        assert_equal "succeeded", run.status
        assert_equal 500, run.imported_count
        assert_operator import_run_selects, :<, (feed_events.size * 2) - 50
      end
    end
  end
end
