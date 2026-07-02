require "test_helper"

module Importing
  module Eventim
    class TicketOfferClassifierTest < ActiveSupport::TestCase
      test "classifies vip package payloads as auxiliary offers" do
        record = build_record(
          title: "Band Live VIP Package",
          raw_payload: {
            "eventid" => "vip-1",
            "eventname" => "Band Live VIP Package",
            "esid" => "series-42",
            "esname" => "Band Live",
            "eventvenue" => "Im Wizemann"
          }
        )

        result = TicketOfferClassifier.call(record)

        assert_equal "auxiliary", result.kind
        assert_equal "series-42", result.series_id
        assert_equal "Band Live", result.series_name
        assert_equal [ "eventim", "series-42", record.start_at.iso8601, "im wizemann" ], result.identity_key
      end

      test "classifies ordinary eventim payloads as main offers" do
        record = build_record(
          title: "Band Live",
          raw_payload: {
            "eventid" => "main-1",
            "eventname" => "Band Live",
            "esid" => "series-42",
            "esname" => "Band Live",
            "eventvenue" => "Im Wizemann"
          }
        )

        result = TicketOfferClassifier.call(record)

        assert_equal "main", result.kind
        assert_equal "series-42", result.series_id
        assert_equal [ "eventim", "series-42", record.start_at.iso8601, "im wizemann" ], result.identity_key
      end

      test "does not build a cross eventim id identity without series id" do
        record = build_record(
          title: "Band Live",
          raw_payload: {
            "eventid" => "main-1",
            "eventname" => "Band Live",
            "eventvenue" => "Im Wizemann"
          }
        )

        result = TicketOfferClassifier.call(record)

        assert_equal "main", result.kind
        assert_nil result.series_id
        assert_nil result.identity_key
      end

      test "does not build a cross eventim id identity from the fallback venue" do
        record = build_record(
          title: "Band Live",
          venue: "Unbekannte Venue",
          raw_payload: {
            "eventid" => "main-1",
            "eventname" => "Band Live",
            "esid" => "series-42",
            "esname" => "Band Live"
          }
        )

        result = TicketOfferClassifier.call(record)

        assert_equal "main", result.kind
        assert_equal "series-42", result.series_id
        assert_nil result.identity_key
      end

      private

      def build_record(title:, raw_payload:, venue: "Im Wizemann")
        Merging::SyncFromImports::ImportRecord.new(
          source: "eventim",
          raw_import_id: 123,
          raw_import_created_at: Time.zone.local(2026, 1, 10, 8, 0, 0),
          source_identifier: "#{raw_payload.fetch("eventid")}:2026-11-10",
          external_event_id: raw_payload.fetch("eventid"),
          series_reference: nil,
          artist_name: title,
          title: title,
          start_at: Time.zone.local(2026, 11, 10, 20, 0, 0),
          doors_at: nil,
          city: "Stuttgart",
          venue: venue,
          promoter_id: nil,
          promoter_name: nil,
          badge_text: nil,
          youtube_url: nil,
          homepage_url: nil,
          facebook_url: nil,
          event_info: nil,
          min_price: nil,
          max_price: nil,
          images: [],
          genre: nil,
          ticket_url: "https://tickets.example/#{raw_payload.fetch("eventid")}",
          ticket_price_text: nil,
          sold_out: false,
          availability_status: "available",
          raw_payload: raw_payload
        )
      end
    end
  end
end
