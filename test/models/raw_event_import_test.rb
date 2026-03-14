require "test_helper"

class RawEventImportTest < ActiveSupport::TestCase
  test "fixture is valid" do
    assert raw_event_imports(:one).valid?
  end
end
