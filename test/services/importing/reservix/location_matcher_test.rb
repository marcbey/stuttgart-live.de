require "test_helper"

module Importing
  module Reservix
    class LocationMatcherTest < ActiveSupport::TestCase
      test "matches reservix references payload" do
        matcher = LocationMatcher.new([ "Stuttgart, Im Wizemann" ])
        payload = {
          "references" => {
            "venue" => [
              {
                "city" => "Stuttgart",
                "formatted" => "Stuttgart, Im Wizemann",
                "name" => "Im Wizemann"
              }
            ]
          }
        }

        assert matcher.match?(payload)
      end
    end
  end
end
