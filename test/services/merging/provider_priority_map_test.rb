require "test_helper"

class Merging::ProviderPriorityMapTest < ActiveSupport::TestCase
  test "returns import priorities from most to least important" do
    priorities = Merging::ProviderPriorityMap.call

    assert_equal 0, priorities["easyticket"]
    assert_equal 10, priorities["reservix"]
    assert_equal 20, priorities["eventim"]
    assert_operator priorities["easyticket"], :<, priorities["reservix"]
    assert_operator priorities["reservix"], :<, priorities["eventim"]
  end
end
