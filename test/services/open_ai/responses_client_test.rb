require "test_helper"
require "uri"

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
      captured_timeout = nil
      fake_credentials = Object.new
      fake_credentials.define_singleton_method(:dig) do |*keys|
        keys == [ :openai, :api_key ] ? "test-openai-key" : nil
      end

      client_class = OpenAI::Client.singleton_class
      client_class.alias_method :__original_new_for_test, :new
      client_class.define_method(:new) do |api_key:, timeout:, **|
        captured_api_key = api_key
        captured_timeout = timeout
        fake_sdk_client
      end

      with_stubbed_credentials(fake_credentials) do
        responses_client = ResponsesClient.new(sdk_client: nil, model: "gpt-5-mini")
        responses_client.send(:client)
      end

      assert_equal "test-openai-key", captured_api_key
      assert_equal ResponsesClient::DEFAULT_TIMEOUT_SECONDS, captured_timeout
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

    test "forwards temperature when configured" do
      captured_request = nil
      fake_sdk_client = build_fake_sdk_client do |request|
        captured_request = request
        { "id" => "resp_123" }
      end
      fake_credentials = fake_credentials_with_api_key

      with_stubbed_credentials(fake_credentials) do
        ResponsesClient.new(model: "gpt-5-mini", temperature: 0.4, sdk_client: fake_sdk_client)
          .create!(input: "Prompt", text_format: { type: "json_schema" })
      end

      assert_equal 0.4, captured_request[:temperature]
    end

    test "omits temperature when not configured" do
      captured_request = nil
      fake_sdk_client = build_fake_sdk_client do |request|
        captured_request = request
        { "id" => "resp_123" }
      end
      fake_credentials = fake_credentials_with_api_key

      with_stubbed_credentials(fake_credentials) do
        ResponsesClient.new(model: "gpt-5-mini", sdk_client: fake_sdk_client)
          .create!(input: "Prompt", text_format: { type: "json_schema" })
      end

      assert_not_includes captured_request.keys, :temperature
    end

    test "retries without temperature when the model does not support it" do
      captured_requests = []
      fake_sdk_client = build_fake_sdk_client do |request|
        captured_requests << request

        if request.key?(:temperature)
          raise StandardError, "Unsupported parameter: 'temperature' is not supported with this model."
        end

        { "id" => "resp_123" }
      end
      fake_credentials = fake_credentials_with_api_key

      with_stubbed_credentials(fake_credentials) do
        ResponsesClient.new(model: "gpt-5-mini", temperature: 1.0, sdk_client: fake_sdk_client)
          .create!(input: "Prompt", text_format: { type: "json_schema" })
      end

      assert_equal 2, captured_requests.size
      assert_equal 1.0, captured_requests.first[:temperature]
      assert_not_includes captured_requests.second.keys, :temperature
    end

    test "preserves quota error details from the sdk" do
      fake_sdk_client = build_fake_sdk_client do |_request|
        raise OpenAI::Errors::RateLimitError.new(
          url: URI("https://api.openai.com/v1/responses"),
          status: 429,
          headers: {},
          body: {
            "message" => "You exceeded your current quota.",
            "type" => "insufficient_quota",
            "code" => "insufficient_quota"
          },
          request: nil,
          response: nil
        )
      end
      fake_credentials = fake_credentials_with_api_key

      with_stubbed_credentials(fake_credentials) do
        error = assert_raises(ResponsesClient::Error) do
          ResponsesClient.new(model: "gpt-5-mini", sdk_client: fake_sdk_client)
            .create!(input: "Prompt", text_format: { type: "json_schema" })
        end

        assert_equal "OpenAI-Kontingent überschritten (HTTP 429): You exceeded your current quota.", error.message
        assert_equal(
          {
            "sdk_error_class" => "OpenAI::Errors::RateLimitError",
            "status" => 429,
            "code" => "insufficient_quota",
            "type" => "insufficient_quota",
            "url" => "https://api.openai.com/v1/responses",
            "body" => {
              "message" => "You exceeded your current quota.",
              "type" => "insufficient_quota",
              "code" => "insufficient_quota"
            }
          },
          error.details_payload
        )
      end
    end

    private

    def build_fake_sdk_client(&block)
      responses_resource = Object.new
      responses_resource.define_singleton_method(:create) do |**request|
        block.call(request)
      end

      Object.new.tap do |sdk_client|
        sdk_client.define_singleton_method(:responses) do
          responses_resource
        end
      end
    end

    def fake_credentials_with_api_key
      Object.new.tap do |credentials|
        credentials.define_singleton_method(:dig) do |*keys|
          keys == [ :openai, :api_key ] ? "test-openai-key" : nil
        end
      end
    end

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
