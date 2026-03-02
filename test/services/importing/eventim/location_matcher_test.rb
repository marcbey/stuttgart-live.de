require "test_helper"

module Importing
  module Eventim
    class LocationMatcherTest < ActiveSupport::TestCase
      test "matches eventim eventplace and eventvenue payload keys" do
        matcher = LocationMatcher.new([ "Stuttgart", "Stuttgart, Im Wizemann" ])
        payload = {
          "eventplace" => "Stuttgart",
          "eventvenue" => "Im Wizemann"
        }

        assert matcher.match?(payload)
      end
    end
  end
end
