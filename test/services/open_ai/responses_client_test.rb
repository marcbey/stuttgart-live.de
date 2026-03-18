require "test_helper"

module OpenAi
  class ResponsesClientTest < ActiveSupport::TestCase
    test "uses credentials api key as fallback" do
      fake_sdk_client = Object.new
      captured_api_key = nil

      client_class = OpenAI::Client.singleton_class
      client_class.alias_method :__original_new_for_test, :new
      client_class.define_method(:new) do |api_key:, **|
        captured_api_key = api_key
        fake_sdk_client
      end

      responses_client = ResponsesClient.new(sdk_client: nil, model: "gpt-5-mini")
      responses_client.send(:client)

      assert_equal Rails.application.credentials.dig(:openai, :api_key).to_s.strip, captured_api_key
    ensure
      client_class.alias_method :new, :__original_new_for_test
      client_class.remove_method :__original_new_for_test
    end
  end
end
