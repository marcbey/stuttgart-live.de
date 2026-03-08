require "test_helper"

module Importing
  module Reservix
    class PayloadProjectionTest < ActiveSupport::TestCase
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
