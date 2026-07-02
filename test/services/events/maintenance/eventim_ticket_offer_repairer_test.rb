require "test_helper"

module Events
  module Maintenance
    class EventimTicketOfferRepairerTest < ActiveSupport::TestCase
      setup do
        RawEventImport.delete_all
      end

      test "reports stale eventim offers in dry run without persisting changes" do
        event = create_event_with_series(name: "& Julia - Das Pop-Musical in Stuttgart")
        create_eventim_offer(event, "old-eventim-id")
        create_eventim_offer(event, "new-eventim-id")
        create_eventim_raw_import(event_id: "old-eventim-id", created_at: Time.zone.local(2026, 1, 10, 8, 0, 0))
        create_eventim_raw_import(event_id: "new-eventim-id", created_at: Time.zone.local(2026, 1, 11, 8, 0, 0))

        result = EventimTicketOfferRepairer.call(
          dry_run: true,
          event_relation: Event.where(id: event.id)
        )

        assert result.dry_run
        assert_equal 1, result.checked_events
        assert_equal 1, result.updated_events
        assert_equal 0, result.created_offers
        assert_equal 1, result.removed_stale_offers
        assert_equal [ "new-eventim-id", "old-eventim-id" ], event.reload.event_offers.where(source: "eventim").order(:source_event_id).pluck(:source_event_id)
        assert_equal 1, result.series_summaries.fetch("& Julia - Das Pop-Musical in Stuttgart").fetch("updated_events")
      end

      test "removes stale eventim offers while keeping manual offers untouched" do
        event = create_event_with_series
        create_eventim_offer(event, "old-eventim-id")
        create_eventim_offer(event, "new-eventim-id")
        manual_offer = event.event_offers.create!(
          source: "manual",
          source_event_id: "manual-ticket",
          ticket_url: "https://tickets.example/manual-ticket",
          priority_rank: 0
        )
        create_eventim_raw_import(event_id: "old-eventim-id", created_at: Time.zone.local(2026, 1, 10, 8, 0, 0))
        create_eventim_raw_import(event_id: "new-eventim-id", created_at: Time.zone.local(2026, 1, 11, 8, 0, 0))

        result = EventimTicketOfferRepairer.call(event_relation: Event.where(id: event.id))

        assert_not result.dry_run
        assert_equal 1, result.checked_events
        assert_equal 1, result.updated_events
        assert_equal 1, result.removed_stale_offers
        assert_equal [ "new-eventim-id" ], event.reload.event_offers.where(source: "eventim").pluck(:source_event_id)
        assert EventOffer.exists?(manual_offer.id)
      end

      test "counts auxiliary eventim records ignored in favor of the main offer" do
        event = create_event_with_series
        create_eventim_offer(event, "main-eventim-id")
        create_eventim_offer(event, "vip-eventim-id")
        create_eventim_raw_import(event_id: "main-eventim-id", created_at: Time.zone.local(2026, 1, 10, 8, 0, 0))
        create_eventim_raw_import(
          event_id: "vip-eventim-id",
          event_name: "Eventim Repair Show VIP Package",
          created_at: Time.zone.local(2026, 1, 11, 8, 0, 0)
        )

        result = EventimTicketOfferRepairer.call(event_relation: Event.where(id: event.id))

        assert_equal 1, result.ignored_auxiliary_records
        assert_equal [ "main-eventim-id" ], event.reload.event_offers.where(source: "eventim").pluck(:source_event_id)
      end

      test "does not report metadata-only updates as repairs" do
        event = create_event_with_series
        create_eventim_offer(event, "current-eventim-id")
        create_eventim_raw_import(event_id: "current-eventim-id", created_at: Time.zone.local(2026, 1, 10, 8, 0, 0))

        result = EventimTicketOfferRepairer.call(
          dry_run: true,
          event_relation: Event.where(id: event.id)
        )

        assert_equal 1, result.checked_events
        assert_equal 0, result.updated_events
        assert_equal 0, result.created_offers
        assert_equal 0, result.removed_stale_offers
      end

      test "leaves mixed eventim series ids unchanged and reports ambiguity" do
        event = create_event_with_series
        create_eventim_offer(event, "eventim-a")
        create_eventim_offer(event, "eventim-b")
        create_eventim_raw_import(event_id: "eventim-a", series_id: "series-a", created_at: Time.zone.local(2026, 1, 10, 8, 0, 0))
        create_eventim_raw_import(event_id: "eventim-b", series_id: "series-b", created_at: Time.zone.local(2026, 1, 11, 8, 0, 0))

        result = EventimTicketOfferRepairer.call(event_relation: Event.where(id: event.id))

        assert_equal 1, result.ambiguous_events
        assert_equal 0, result.updated_events
        assert_equal [ "eventim-a", "eventim-b" ], event.reload.event_offers.where(source: "eventim").order(:source_event_id).pluck(:source_event_id)
      end

      private

      def create_event_with_series(name: "Eventim Repair Series")
        series = EventSeries.create!(origin: "imported", source_type: "eventim", source_key: "eventim-repair-series", name: name)
        Event.create!(
          slug: "eventim-repair-#{SecureRandom.hex(4)}",
          source_fingerprint: "test::eventim-repair::#{SecureRandom.hex(4)}",
          title: "Eventim Repair Show",
          artist_name: "Eventim Repair Band",
          start_at: Time.zone.local(2026, 11, 10, 20, 0, 0),
          venue: "Im Wizemann",
          city: "Stuttgart",
          status: "published",
          event_series: series,
          event_series_assignment: "auto",
          source_snapshot: {}
        )
      end

      def create_eventim_offer(event, event_id)
        event.event_offers.create!(
          source: "eventim",
          source_event_id: event_id,
          ticket_url: "https://tickets.example/#{event_id}",
          priority_rank: 10
        )
      end

      def create_eventim_raw_import(event_id:, created_at:, event_name: "Eventim Repair Show", series_id: "eventim-repair-series")
        RawEventImport.create!(
          import_source: import_sources(:two),
          import_event_type: "eventim",
          source_identifier: "#{event_id}:2026-11-10",
          created_at: created_at,
          updated_at: created_at,
          payload: {
            "eventid" => event_id,
            "eventdate" => "2026-11-10",
            "eventtime" => "20:00",
            "eventplace" => "Stuttgart",
            "eventvenue" => "Im Wizemann",
            "eventname" => event_name,
            "artistname" => "Eventim Repair Band",
            "esid" => series_id,
            "esname" => "Eventim Repair Series",
            "eventlink" => "https://tickets.example/#{event_id}"
          }
        )
      end
    end
  end
end
