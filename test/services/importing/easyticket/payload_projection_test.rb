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
        assert_equal "https://img.example/large.jpg", attributes[:image_url]
        assert_equal "https://tickets.example/42", attributes[:ticket_url]
      end
    end
  end
end
