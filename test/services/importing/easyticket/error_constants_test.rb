require "test_helper"

module Importing
  module Easyticket
    class ErrorConstantsTest < ActiveSupport::TestCase
      test "request_error is a subclass of easyticket error" do
        assert RequestError < Error
      end

      test "parsing_error is a subclass of easyticket error" do
        assert ParsingError < Error
      end

      test "run_already_active_error is a subclass of easyticket error" do
        assert RunAlreadyActiveError < Error
      end
    end
  end
end
