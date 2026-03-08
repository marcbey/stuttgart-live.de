require "test_helper"

module Importing
  module Easyticket
    class PayloadProjectionTest < ActiveSupport::TestCase
      test "supports events api event_dates payload and image index" do
        projection = PayloadProjection.new(
          dump_payload: {
            "event_id" => "42",
            "date_time" => "2026-06-17 20:00:00",
            "location_name" => "Im Wizemann Stuttgart",
            "title_1" => "The Band",
            "title_2" => "Live",
            "organizer_id" => "141",
            "data" => {
              "event" => {
                "title_1" => "The Band",
                "title_2" => "Live"
              },
              "location" => {
                "name" => "Im Wizemann",
                "city" => "Stuttgart"
              },
              "images" => {
                "42" => {
                  "small" => "https://img.example/small.jpg",
                  "large" => {
                    "url" => "https://img.example/large.jpg"
                  }
                }
              }
            }
          },
          detail_payload: {
            "data" => {
              "organizer_name" => "Music Circus GmbH & Co. KG"
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
        assert_equal [ "small", "large" ], image_candidates.map { |candidate| candidate[:image_type] }
      end

      test "falls back to detail payload images when dump image index is missing" do
        projection = PayloadProjection.new(
          dump_payload: {
            "event_id" => "42",
            "date_time" => "2026-06-17 20:00:00",
            "location_name" => "Im Wizemann Stuttgart",
            "title_1" => "The Band"
          },
          detail_payload: {
            "data" => {
              "images" => [
                {
                  "paths" => [
                    { "type" => "large", "url" => "https://img.example/detail-large.jpg" }
                  ]
                }
              ]
            }
          },
          ticket_base_url: "https://tickets.example/%{event_id}"
        )

        assert_equal [ "https://img.example/detail-large.jpg" ],
          projection.image_candidates.map { |candidate| candidate[:image_url] }
      end

      test "replaces curly event_id placeholder in ticket base url" do
        projection = PayloadProjection.new(
          dump_payload: {
            "event_id" => "99",
            "date_time" => "2026-06-20 19:30:00",
            "location_name" => "LKA Stuttgart",
            "title_1" => "Another Band"
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
            "date_time" => "2026-06-20 19:30:00",
            "location_name" => "LKA Stuttgart",
            "title_1" => "Another Band"
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
