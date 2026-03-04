require "test_helper"

module Importing
  module Easyticket
    class PayloadProjectionTest < ActiveSupport::TestCase
      test "supports detail data wrapper and large image path" do
        projection = PayloadProjection.new(
          dump_payload: {
            "event_id" => "42",
            "date" => "2026-06-17",
            "loc_city" => "Stuttgart",
            "loc_name" => "Im Wizemann",
            "title" => "The Band",
            "sub1" => "1234"
          },
          detail_payload: {
            "data" => {
              "organizer_name" => "Music Circus GmbH & Co. KG",
              "organizer_id" => "141",
              "images" => [
                {
                  "paths" => [
                    { "type" => "small", "url" => "https://img.example/small.jpg" },
                    { "type" => "large", "url" => "https://img.example/large.jpg" }
                  ]
                }
              ]
            }
          },
          ticket_base_url: "https://tickets.example/%{event_id}"
        )

        attributes = projection.to_attributes

        assert_equal "42", attributes[:external_event_id]
        assert_equal Date.new(2026, 6, 17), attributes[:concert_date]
        assert_equal "17.6.2026", attributes[:concert_date_label]
        assert_equal "Stuttgart, Im Wizemann", attributes[:venue_label]
        assert_equal "The Band", attributes[:artist_name]
        assert_equal "Music Circus GmbH & Co. KG", attributes[:organizer_name]
        assert_equal "141", attributes[:organizer_id]
        assert_equal "https://tickets.example/42", attributes[:ticket_url]

        image_candidates = projection.image_candidates
        assert_equal [ "https://img.example/small.jpg", "https://img.example/large.jpg" ],
          image_candidates.map { |candidate| candidate[:image_url] }
      end

      test "replaces curly event_id placeholder in ticket base url" do
        projection = PayloadProjection.new(
          dump_payload: {
            "event_id" => "99",
            "date" => "2026-06-20",
            "loc_city" => "Stuttgart",
            "loc_name" => "LKA",
            "title" => "Another Band"
          },
          detail_payload: {},
          ticket_base_url: "https://tickets.example/event/{event_id}"
        )

        attributes = projection.to_attributes

        assert_equal "https://tickets.example/event/99", attributes[:ticket_url]
      end

      test "does not append event_id twice when base already ends with id" do
        projection = PayloadProjection.new(
          dump_payload: {
            "event_id" => "104364",
            "date" => "2026-06-20",
            "loc_city" => "Stuttgart",
            "loc_name" => "LKA",
            "title" => "Another Band"
          },
          detail_payload: {},
          ticket_base_url: "https://partnershop.easyticket.de/shop/event/104364"
        )

        attributes = projection.to_attributes

        assert_equal "https://partnershop.easyticket.de/shop/event/104364", attributes[:ticket_url]
      end
    end
  end
end
