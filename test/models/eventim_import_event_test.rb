require "test_helper"

class EventimImportEventTest < ActiveSupport::TestCase
  test "fixture is valid" do
    assert eventim_import_events(:one).valid?
  end
end
