require "test_helper"

module Importing
  module Reservix
    class PayloadProjectionTest < ActiveSupport::TestCase
      test "extracts doors_time from known reservix payload keys" do
        projection = PayloadProjection.new(
          event_payload: {
            "id" => "rvx-41",
            "name" => "Reservix Event",
            "artist" => "Reservix Artist",
            "startdate" => "2026-07-12",
            "doorsOpen" => "18:15",
            "references" => {
              "venue" => [ { "name" => "LKA Longhorn", "city" => "Stuttgart" } ]
            }
          }
        )

        attributes = projection.to_attributes

        assert_equal "18:15", attributes[:doors_time]
      end

      test "keeps city blank when payload does not provide one" do
        projection = PayloadProjection.new(
          event_payload: {
            "id" => "rvx-42",
            "name" => "Reservix Event",
            "artist" => "Reservix Artist",
            "startdate" => "2026-07-12",
            "references" => {
              "venue" => [ { "name" => "LKA Longhorn" } ]
            }
          }
        )

        attributes = projection.to_attributes

        assert_nil attributes[:city]
        assert_equal "LKA Longhorn", attributes[:venue_name]
      end
    end
  end
end
