require "test_helper"

module Importing
  module Reservix
    class ImporterTest < ActiveSupport::TestCase
      class StubEventFetcher
        attr_reader :lastupdate_arguments

        def initialize(pages)
          @pages = pages
          @lastupdate_arguments = []
        end

        def fetch_pages(lastupdate:, heartbeat:, stop_requested: nil)
          @lastupdate_arguments << lastupdate
          @pages.each do |page|
            heartbeat&.call
            yield(page.fetch(:events), server_time: page.fetch(:server_time))
          end
        end
      end

      setup do
        @source = ImportSource.ensure_reservix_source!
        (@source.import_source_config || @source.build_import_source_config).tap do |config|
          config.location_whitelist = [ "Stuttgart" ]
          config.save!
        end
      end

      test "imports paged bookable rows into raw_event_imports and persists checkpoint" do
        fetcher = StubEventFetcher.new(
          [
            {
              server_time: Time.zone.parse("2026-03-14 10:00:00"),
              events: [
                {
                  "id" => "rvx-1",
                  "name" => "Reservix Show",
                  "artist" => "Reservix Artist",
                  "bookable" => true,
                  "modified" => "2026-03-14T09:00:00+01:00",
                  "startdate" => "2026-04-20",
                  "references" => {
                    "venue" => [ { "name" => "Im Wizemann", "city" => "Stuttgart" } ],
                    "eventgroup" => [ { "id" => "group-1", "name" => "Reservix Reihe" } ]
                  }
                }
              ]
            },
            {
              server_time: Time.zone.parse("2026-03-14 10:05:00"),
              events: [
                {
                  "id" => "rvx-2",
                  "name" => "Filtered Show",
                  "artist" => "Filtered Artist",
                  "bookable" => true,
                  "modified" => "2026-03-14T10:01:00+01:00",
                  "startdate" => "2026-04-21",
                  "references" => {
                    "venue" => [ { "name" => "Tempodrom", "city" => "Berlin" } ]
                  }
                }
              ]
            }
          ]
        )

        run = Importer.new(
          import_source: @source,
          event_fetcher: fetcher
        ).call

        imported = RawEventImport.find_by!(
          import_source: @source,
          import_event_type: "reservix",
          source_identifier: "rvx-1"
        )

        assert_equal "succeeded", run.status
        assert_equal 2, run.fetched_count
        assert_equal 1, run.filtered_count
        assert_equal 1, run.imported_count
        assert_equal 1, run.upserted_count
        assert_equal 0, run.failed_count
        assert_nil fetcher.lastupdate_arguments.first
        assert_equal "rvx-1", imported.payload["id"]
        assert_equal "Berlin", run.metadata.fetch("filtered_out_cities").first
        assert_equal "Reservix Reihe",
          EventSeries.imported.find_by!(source_type: "reservix", source_key: "group-1").name

        checkpoint = @source.reload.import_source_config.reservix_checkpoint
        assert_equal "2026-03-14T10:05:00+01:00", checkpoint["lastupdate"]
        assert_nil checkpoint["last_processed_event_id"]
      end

      test "cancels run when stop is requested during page fetching" do
        canceling_fetcher = Class.new do
          def fetch_pages(lastupdate:, heartbeat:, stop_requested: nil)
            heartbeat&.call
            raise Importing::StopRequested if stop_requested&.call
          end
        end.new

        run = @source.import_runs.create!(
          status: "running",
          source_type: "reservix",
          started_at: 1.minute.ago,
          metadata: {
            "execution_started_at" => 1.minute.ago.iso8601,
            "stop_requested" => true,
            "stop_requested_at" => 30.seconds.ago.iso8601
          }
        )

        result = Importer.new(
          import_source: @source,
          event_fetcher: canceling_fetcher,
          preexisting_run_id: run.id
        ).call

        assert_equal "canceled", result.reload.status
        assert result.finished_at.present?
      end

      test "touches heartbeat while processing page events" do
        heartbeatless_fetcher = Class.new do
          def initialize(page)
            @page = page
          end

          def fetch_pages(lastupdate:, heartbeat:, stop_requested: nil)
            yield(@page.fetch(:events), server_time: @page.fetch(:server_time))
          end
        end.new(
          server_time: Time.zone.parse("2026-03-14 10:00:00"),
          events: 5.times.map do |index|
            {
              "id" => "rvx-heartbeat-#{index}",
              "name" => "Reservix #{index}",
              "artist" => "Artist #{index}",
              "bookable" => true,
              "modified" => "2026-03-14T09:00:00+01:00",
              "startdate" => "2026-04-20",
              "references" => {
                "venue" => [ { "name" => "Im Wizemann", "city" => "Stuttgart" } ]
              }
            }
          end
        )

        importer_class = Class.new(Importer) do
          attr_reader :heartbeat_calls

          def initialize(...)
            super
            @heartbeat_calls = 0
          end

          private

          def touch_run_heartbeat!(run, extra_metadata: nil)
            @heartbeat_calls += 1
            super
          end

          def processing_heartbeat_every_n_rows
            2
          end
        end

        importer = importer_class.new(
          import_source: @source,
          event_fetcher: heartbeatless_fetcher
        )

        run = importer.call

        assert_equal "succeeded", run.status
        assert_operator importer.heartbeat_calls, :>=, 2
      end
    end
  end
end
