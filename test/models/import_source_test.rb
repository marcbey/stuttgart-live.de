require "test_helper"

class ImportSourceTest < ActiveSupport::TestCase
  test "ensure_easyticket_source creates default location whitelist" do
    existing_source = ImportSource.find_by(source_type: "easyticket")
    existing_source&.destroy!

    source = ImportSource.ensure_easyticket_source!

    assert_equal "easyticket", source.source_type
    assert_equal ImportSource::DEFAULT_EASYTICKET_LOCATION_WHITELIST, source.configured_location_whitelist
  end

  test "ensure_eventim_source creates source with location whitelist" do
    existing_source = ImportSource.find_by(source_type: "eventim")
    existing_source&.destroy!

    source = ImportSource.ensure_eventim_source!

    assert_equal "eventim", source.source_type
    assert_equal ImportSource::DEFAULT_EASYTICKET_LOCATION_WHITELIST, source.configured_location_whitelist
  end
end
