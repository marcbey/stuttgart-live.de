require "test_helper"

module OpenAi
  class ResponsesClientTest < ActiveSupport::TestCase
    test "falls back to default model when configured model is blank" do
      responses_client = ResponsesClient.new(model: " \n\t")

      assert_equal "gpt-5.1", responses_client.model
    end

    test "uses llm enrichment model from app settings by default" do
      AppSetting.where(key: AppSetting::LLM_ENRICHMENT_MODEL_KEY).delete_all
      AppSetting.create!(key: AppSetting::LLM_ENRICHMENT_MODEL_KEY, value: "gpt-5-mini")
      AppSetting.reset_cache!

      responses_client = ResponsesClient.new

      assert_equal "gpt-5-mini", responses_client.model
    ensure
      AppSetting.where(key: AppSetting::LLM_ENRICHMENT_MODEL_KEY).delete_all
      AppSetting.reset_cache!
    end

    test "uses api key from rails credentials" do
      fake_sdk_client = Object.new
      captured_api_key = nil
      fake_credentials = Object.new
      fake_credentials.define_singleton_method(:dig) do |*keys|
        keys == [ :openai, :api_key ] ? "test-openai-key" : nil
      end

      client_class = OpenAI::Client.singleton_class
      client_class.alias_method :__original_new_for_test, :new
      client_class.define_method(:new) do |api_key:, **|
        captured_api_key = api_key
        fake_sdk_client
      end

      with_stubbed_credentials(fake_credentials) do
        responses_client = ResponsesClient.new(sdk_client: nil, model: "gpt-5-mini")
        responses_client.send(:client)
      end

      assert_equal "test-openai-key", captured_api_key
    ensure
      client_class.alias_method :new, :__original_new_for_test
      client_class.remove_method :__original_new_for_test
    end

    test "raises when api key is missing in rails credentials" do
      fake_credentials = Object.new
      fake_credentials.define_singleton_method(:dig) do |*|
        nil
      end

      with_stubbed_credentials(fake_credentials) do
        error = assert_raises(ResponsesClient::Error) do
          ResponsesClient.new(model: "gpt-5-mini").create!(input: [], text_format: {})
        end

        assert_equal "openai.api_key ist nicht in den Rails Credentials gesetzt.", error.message
      end
    end

    private

    def with_stubbed_credentials(fake_credentials)
      application_class = Rails.application.singleton_class
      application_class.alias_method :__original_credentials_for_test, :credentials
      application_class.define_method(:credentials) do
        fake_credentials
      end

      yield
    ensure
      application_class.alias_method :credentials, :__original_credentials_for_test
      application_class.remove_method :__original_credentials_for_test
    end
  end
end
