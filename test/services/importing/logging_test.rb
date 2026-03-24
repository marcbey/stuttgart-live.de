require "test_helper"

class Importing::LoggingTest < ActiveSupport::TestCase
  test "uses the shared Rails logger" do
    assert_same Rails.logger, Importing::Logging.logger
  end
end
