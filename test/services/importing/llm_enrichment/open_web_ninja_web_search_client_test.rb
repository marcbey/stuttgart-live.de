require "test_helper"

module Importing
  module LlmEnrichment
    class OpenWebNinjaWebSearchClientTest < ActiveSupport::TestCase
      FakeStatus = Struct.new(:successful, :exitstatus) do
        def success?
          successful
        end
      end

      test "returns parsed organic results" do
        response = [
          {
            "request_id" => "req-123",
            "data" => {
              "organic_results" => [
                {
                  "position" => 1,
                  "url" => "https://example.com",
                  "title" => "Example",
                  "snippet" => "Snippet"
                }
              ]
            }
          }.to_json,
          "200"
        ].join("\n#{OpenWebNinjaHttp::STATUS_MARKER}:")

        result = with_curl_response(stdout: response) do
          OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
        end

        assert_equal "req-123", result.search_id
        assert_equal 1, result.organic_results.first.position
        assert_equal "https://example.com", result.organic_results.first.link
        assert_equal "", result.organic_results.first.displayed_link
      end

      test "raises on api errors" do
        response = [
          { "error" => { "message" => "invalid key", "code" => 401 } }.to_json,
          "401"
        ].join("\n#{OpenWebNinjaHttp::STATUS_MARKER}:")

        error = assert_raises(OpenWebNinjaWebSearchClient::Error) do
          with_curl_response(stdout: response) do
            OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
          end
        end

        assert_includes error.message, "invalid key"
      end

      test "raises on invalid json" do
        response = "{\n#{OpenWebNinjaHttp::STATUS_MARKER}:200"

        error = assert_raises(OpenWebNinjaWebSearchClient::Error) do
          with_curl_response(stdout: response) do
            OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
          end
        end

        assert_includes error.message, "ungültiges JSON"
      end

      test "raises on curl execution errors" do
        error = assert_raises(OpenWebNinjaWebSearchClient::Error) do
          with_curl_response(stdout: "", stderr: "curl: (28) timed out", success: false, exitstatus: 28) do
            OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
          end
        end

        assert_includes error.message, "timed out"
      end

      test "raises when api key is missing" do
        error = assert_raises(OpenWebNinjaWebSearchClient::Error) do
          OpenWebNinjaWebSearchClient.new(api_key: nil).search(query: "\"Luca Noel\"")
        end

        assert_includes error.message, "OPENWEBNINJA_API_KEY fehlt"
      end

      private

      def with_curl_response(stdout:, stderr: "", success: true, exitstatus: 0)
        original_capture3 = Open3.method(:capture3)
        status = FakeStatus.new(success, exitstatus)

        Open3.singleton_class.define_method(:capture3) do |*args|
          [ stdout, stderr, status ]
        end

        yield
      ensure
        Open3.singleton_class.define_method(:capture3, original_capture3)
      end
    end
  end
end
