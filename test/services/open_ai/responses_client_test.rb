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

    test "uses credentials and allows a responses request that takes four minutes" do
      authorization = nil
      timeout = nil
      transport = Object.new
      transport.define_singleton_method(:execute) do |request|
        authorization = request.headers.fetch("authorization")
        timeout = request.timeout
        raise OpenAI::Errors::APITimeoutError.new(url: request.url) if request.timeout < 240

        OpenAI::HTTPClient::Response.new(
          status: 200,
          headers: { "content-type" => "application/json" },
          body: { id: "resp_test", object: "response", status: "completed", output: [] }.to_json
        )
      end

      transport_class = OpenAI::NetHTTPClient.singleton_class
      transport_class.alias_method :__original_new_for_test, :new
      transport_class.define_method(:new) { transport }

      with_stubbed_credentials(fake_credentials_with_api_key) do
        response = ResponsesClient.new(model: "gpt-5-mini").create!(input: "Prompt", text_format: structured_text_format)

        assert_equal "resp_test", response.id
      end

      assert_equal "Bearer test-openai-key", authorization
      assert_equal 300.0, timeout
    rescue ResponsesClient::Error => error
      flunk("Expected the slow response to complete, but got #{error.message}")
    ensure
      transport_class.alias_method :new, :__original_new_for_test
      transport_class.remove_method :__original_new_for_test
    end

    test "raises when api key is missing in rails credentials" do
      fake_credentials = Object.new
      fake_credentials.define_singleton_method(:dig) do |*|
        nil
      end

      with_stubbed_credentials(fake_credentials) do
        error = assert_raises(ResponsesClient::Error) do
          ResponsesClient.new(model: "gpt-5-mini").create!(input: [], text_format: structured_text_format)
        end

        assert_equal "openai.api_key ist nicht in den Rails Credentials gesetzt.", error.message
      end
    end

    test "creates responses api request with structured output text format" do
      captured_request = nil
      fake_sdk_client = build_fake_sdk_client do |request|
        captured_request = request
        { "id" => "resp_123" }
      end
      fake_credentials = fake_credentials_with_api_key

      with_stubbed_credentials(fake_credentials) do
        ResponsesClient.new(model: "gpt-5-mini", sdk_client: fake_sdk_client)
          .create!(input: "Prompt", text_format: structured_text_format)
      end

      assert_equal "gpt-5-mini", captured_request.fetch(:model)
      assert_equal "Prompt", captured_request.fetch(:input)
      assert_equal structured_text_format, captured_request.dig(:text, :format)
      assert_equal "json_schema", captured_request.dig(:text, :format, :type)
      assert_equal true, captured_request.dig(:text, :format, :strict)
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
          .create!(input: "Prompt", text_format: structured_text_format)
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
          .create!(input: "Prompt", text_format: structured_text_format)
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
          .create!(input: "Prompt", text_format: structured_text_format)
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
            message: "You exceeded your current quota.",
            type: "insufficient_quota",
            code: "insufficient_quota"
          },
          request: nil,
          response: nil
        )
      end
      fake_credentials = fake_credentials_with_api_key

      with_stubbed_credentials(fake_credentials) do
        error = assert_raises(ResponsesClient::Error) do
          ResponsesClient.new(model: "gpt-5-mini", sdk_client: fake_sdk_client)
            .create!(input: "Prompt", text_format: structured_text_format)
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

    test "recognizes quota metadata in string keyed error bodies" do
      bodies = [
        { "message" => "No credits remain.", "code" => "insufficient_quota" },
        { "message" => "No credits remain.", "type" => "insufficient_quota" },
        { "message" => "You exceeded your current quota." }
      ]

      bodies.each do |body|
        fake_sdk_client = build_fake_sdk_client do |_request|
          raise OpenAI::Errors::RateLimitError.new(
            url: URI("https://api.openai.com/v1/responses"),
            status: 429,
            headers: {},
            body: body,
            request: nil,
            response: nil
          )
        end

        with_stubbed_credentials(fake_credentials_with_api_key) do
          error = assert_raises(ResponsesClient::Error) do
            ResponsesClient.new(model: "gpt-5-mini", sdk_client: fake_sdk_client)
              .create!(input: "Prompt", text_format: structured_text_format)
          end

          assert_equal "OpenAI-Kontingent überschritten (HTTP 429): #{body.fetch('message')}", error.message
          assert_equal body, error.details_payload.fetch("body")
        end
      end
    end

    test "keeps ordinary rate limits distinct when quota metadata is absent" do
      [ { "message" => "Too many requests.", "code" => "rate_limit_exceeded" }, nil, "Temporary rate limit" ].each do |body|
        fake_sdk_client = build_fake_sdk_client do |_request|
          raise OpenAI::Errors::RateLimitError.new(
            url: URI("https://api.openai.com/v1/responses"),
            status: 429,
            headers: {},
            body: body,
            request: nil,
            response: nil
          )
        end

        with_stubbed_credentials(fake_credentials_with_api_key) do
          error = assert_raises(ResponsesClient::Error) do
            ResponsesClient.new(model: "gpt-5-mini", sdk_client: fake_sdk_client)
              .create!(input: "Prompt", text_format: structured_text_format)
          end

          assert_match(/\AOpenAI-Rate-Limit erreicht \(HTTP 429\): /, error.message)
          assert_equal 429, error.details_payload.fetch("status")
        end
      end
    end

    private

    def structured_text_format
      Importing::LlmEnrichment::OutputSchema.format
    end

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
