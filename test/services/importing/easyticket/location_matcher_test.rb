require "test_helper"

module Importing
  module Easyticket
    class LocationMatcherTest < ActiveSupport::TestCase
      test "matches normalized city and venue combinations" do
        matcher = LocationMatcher.new([ "Stuttgart", "Im Wizemann" ])
        payload = {
          "loc_city" => "Stüttgart",
          "location_name" => "Im Wizemann"
        }

        assert matcher.match?(payload)
      end
    end
  end
end
