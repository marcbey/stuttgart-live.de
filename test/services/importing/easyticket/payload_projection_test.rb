require "test_helper"

module Importing
  module Easyticket
    class PayloadProjectionTest < ActiveSupport::TestCase
      test "supports events api event_dates payload and image index" do
        projection = PayloadProjection.new(
          dump_payload: {
            "id" => "4200",
            "event_id" => "42",
            "title_3" => "4200",
            "date_time" => "2026-06-17 20:00:00",
            "doors_at" => "18:30",
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
              "organizer_id" => "141"
            }
          },
          ticket_base_url: "https://tickets.example/%{event_id}"
        )

        attributes = projection.to_attributes

        assert_equal "42", attributes[:external_event_id]
        assert_equal Date.new(2026, 6, 17), attributes[:concert_date]
        assert_equal "17.6.2026", attributes[:concert_date_label]
        assert_equal "Stuttgart, Im Wizemann", attributes[:venue_label]
        assert_equal "Live", attributes[:title]
        assert_equal "The Band", attributes[:artist_name]
        assert_equal "141", attributes[:organizer_id]
        assert_equal "18:30", attributes[:doors_time]
        assert_equal "https://tickets.example/4200", attributes[:ticket_url]

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
            "id" => "9900",
            "event_id" => "99",
            "title_3" => "9900",
            "date_time" => "2026-06-20 19:30:00",
            "location_name" => "LKA Stuttgart",
            "title_1" => "Another Band"
          },
          detail_payload: {},
          ticket_base_url: "https://tickets.example/event/{event_id}"
        )

        attributes = projection.to_attributes

        assert_equal "https://tickets.example/event/9900", attributes[:ticket_url]
      end

      test "does not append payload id twice when base already ends with id" do
        projection = PayloadProjection.new(
          dump_payload: {
            "id" => "559977",
            "event_id" => "104364",
            "title_3" => "559977",
            "date_time" => "2026-06-20 19:30:00",
            "location_name" => "LKA Stuttgart",
            "title_1" => "Another Band"
          },
          detail_payload: {},
          ticket_base_url: "https://partnershop.easyticket.de/shop/event/559977"
        )

        attributes = projection.to_attributes

        assert_equal "https://partnershop.easyticket.de/shop/event/559977", attributes[:ticket_url]
      end

      test "falls back to external event id when payload id is missing" do
        projection = PayloadProjection.new(
          dump_payload: {
            "event_id" => "104364",
            "date_time" => "2026-06-20 19:30:00",
            "location_name" => "LKA Stuttgart",
            "title_1" => "Another Band"
          },
          detail_payload: {},
          ticket_base_url: "https://tickets.example/event/{event_id}"
        )

        attributes = projection.to_attributes

        assert_equal "https://tickets.example/event/104364", attributes[:ticket_url]
      end

      test "uses payload id when title_3 is descriptive text" do
        projection = PayloadProjection.new(
          dump_payload: {
            "id" => "105758",
            "event_id" => "104364",
            "title_3" => "The Beast Goes On",
            "date_time" => "2026-06-20 19:30:00",
            "location_name" => "LKA Stuttgart",
            "title_1" => "Another Band"
          },
          detail_payload: {},
          ticket_base_url: "https://tickets.example/event/{event_id}"
        )

        attributes = projection.to_attributes

        assert_equal "https://tickets.example/event/105758", attributes[:ticket_url]
      end

      test "uses payload id when title_3 contains non id characters" do
        projection = PayloadProjection.new(
          dump_payload: {
            "id" => "105326",
            "event_id" => "62290",
            "title_3" => "105326+",
            "date_time" => "2026-07-17 19:30:00",
            "location_name" => "LKA Stuttgart",
            "title_1" => "Splendid"
          },
          detail_payload: {},
          ticket_base_url: "https://tickets.example/event/{event_id}"
        )

        attributes = projection.to_attributes

        assert_equal "https://tickets.example/event/105326", attributes[:ticket_url]
      end

      test "infers city from location name suffix when no explicit city is present" do
        projection = PayloadProjection.new(
          dump_payload: {
            "event_id" => "104364",
            "date_time" => "2026-06-20 19:30:00",
            "location_name" => "LKA Stuttgart",
            "title_1" => "Another Band"
          },
          detail_payload: {}
        )

        attributes = projection.to_attributes

        assert_equal "Stuttgart", attributes[:city]
      end

      test "infers multi word city from trailing location name segment" do
        projection = PayloadProjection.new(
          dump_payload: {
            "event_id" => "104365",
            "date_time" => "2026-06-20 19:30:00",
            "location_name" => "Neckar Forum Esslingen am Neckar",
            "title_1" => "Another Band"
          },
          detail_payload: {}
        )

        attributes = projection.to_attributes

        assert_equal "Esslingen am Neckar", attributes[:city]
      end
    end
  end
end
