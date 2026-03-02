require "test_helper"

class ImportSourceConfigTest < ActiveSupport::TestCase
  test "normalizes location whitelist from text" do
    config = import_source_configs(:one)
    config.location_whitelist = "Stuttgart\nEsslingen am Neckar, Stuttgart"

    assert_equal [ "Stuttgart", "Esslingen am Neckar" ], config.location_whitelist
  end
end
