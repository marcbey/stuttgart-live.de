require "test_helper"

module Events
  module Maintenance
    class EasyticketTicketUrlRepairerTest < ActiveSupport::TestCase
      setup do
        RawEventImport.delete_all
      end

      test "updates persisted easyticket ticket urls from payload id" do
        event = create_event
        offer = event.event_offers.create!(
          source: "easyticket",
          source_event_id: "62721",
          ticket_url: "https://partnershop.easyticket.de/shop/event/The Beast Goes On",
          ticket_price_text: "24,95 EUR",
          priority_rank: 0
        )
        raw_import = create_raw_import

        with_easyticket_ticket_base_url("https://partnershop.easyticket.de/shop/event/{event_id}") do
          result = EasyticketTicketUrlRepairer.call(
            offer_relation: EventOffer.where(id: offer.id),
            raw_import_relation: RawEventImport.where(id: raw_import.id)
          )

          assert_equal 1, result.checked_count
          assert_equal 1, result.updated_count
          assert_equal 0, result.unchanged_count
          assert_equal "https://partnershop.easyticket.de/shop/event/105758", offer.reload.ticket_url
        end
      end

      test "does not persist changes in dry run mode" do
        event = create_event
        offer = event.event_offers.create!(
          source: "easyticket",
          source_event_id: "62721",
          ticket_url: "https://partnershop.easyticket.de/shop/event/The Beast Goes On",
          priority_rank: 0
        )
        raw_import = create_raw_import

        with_easyticket_ticket_base_url("https://partnershop.easyticket.de/shop/event/{event_id}") do
          result = EasyticketTicketUrlRepairer.call(
            dry_run: true,
            offer_relation: EventOffer.where(id: offer.id),
            raw_import_relation: RawEventImport.where(id: raw_import.id)
          )

          assert result.dry_run
          assert_equal 1, result.updated_count
          assert_equal "https://partnershop.easyticket.de/shop/event/The Beast Goes On", offer.reload.ticket_url
        end
      end

      test "counts offers without matching raw imports" do
        event = create_event
        event.event_offers.create!(
          source: "easyticket",
          source_event_id: "missing",
          ticket_url: "https://partnershop.easyticket.de/shop/event/missing",
          priority_rank: 0
        )

        result = EasyticketTicketUrlRepairer.call(offer_relation: EventOffer.where(id: event.event_offers.select(:id)))

        assert_equal 1, result.checked_count
        assert_equal 1, result.missing_raw_import_count
        assert_equal 0, result.updated_count
      end

      private

      def create_event
        Event.create!(
          slug: "starbenders-2026-06-16",
          source_fingerprint: "test::starbenders",
          title: "The Beast goes on Tour",
          artist_name: "Starbenders",
          start_at: Time.zone.local(2026, 6, 16, 20, 0, 0),
          venue: "Goldmarks",
          city: "Stuttgart",
          status: "published",
          source_snapshot: {}
        )
      end

      def create_raw_import
        RawEventImport.create!(
          import_source: import_sources(:one),
          import_event_type: "easyticket",
          source_identifier: "62721:2026-06-16",
          payload: {
            "id" => "105758",
            "event_id" => "62721",
            "date_time" => "2026-06-16 20:00:00",
            "loc_city" => "Stuttgart",
            "loc_name" => "Goldmarks",
            "title_1" => "Starbenders",
            "title_2" => "The Beast goes on Tour",
            "title_3" => "The Beast Goes On"
          }
        )
      end

      def with_easyticket_ticket_base_url(value)
        original = AppConfig.method(:easyticket_ticket_link_event_base_url)
        AppConfig.define_singleton_method(:easyticket_ticket_link_event_base_url) { value }
        yield
      ensure
        AppConfig.define_singleton_method(:easyticket_ticket_link_event_base_url, original)
      end
    end
  end
end
