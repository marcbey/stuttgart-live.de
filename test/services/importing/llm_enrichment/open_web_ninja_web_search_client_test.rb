require "test_helper"

module Importing
  module LlmEnrichment
    class OpenWebNinjaWebSearchClientTest < ActiveSupport::TestCase
      FakeResponse = Struct.new(:code, :body) do
        def is_a?(klass)
          klass == Net::HTTPSuccess ? code.to_s.start_with?("2") : super
        end
      end

      test "returns parsed top-level organic results" do
        response = FakeResponse.new(
          "200",
          {
            "request_id" => "req-123",
            "organic_results" => [
              {
                "position" => 1,
                "url" => "https://example.com",
                "title" => "Example",
                "snippet" => "Snippet",
                "displayed_link" => "https://example.com",
                "source" => "Example"
              }
            ]
          }.to_json
        )

        result = with_http_response(response) do
          OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
        end

        assert_equal "req-123", result.search_id
        assert_equal 1, result.organic_results.first.position
        assert_equal "https://example.com", result.organic_results.first.link
        assert_equal "https://example.com", result.organic_results.first.displayed_link
        assert_equal "Example", result.organic_results.first.source
        assert_equal "application/json", @captured_request["Accept"]
        assert_equal "secret", @captured_request["X-API-Key"]
        assert_includes @captured_request.uri.query, "q=%22Luca+Noel%22"
        assert_includes @captured_request.uri.query, "num=10"
        assert_includes @captured_request.uri.query, "location=Germany"
        assert_includes @captured_request.uri.query, "hl=de"
        assert_includes @captured_request.uri.query, "gl=de"
      end

      test "returns parsed legacy data organic results" do
        response = FakeResponse.new(
          "200",
          {
            "request_id" => "req-legacy",
            "data" => {
              "organic_results" => [
                {
                  "position" => 2,
                  "link" => "https://legacy.example.com",
                  "title" => "Legacy"
                }
              ]
            }
          }.to_json
        )

        result = with_http_response(response) do
          OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
        end

        assert_equal "req-legacy", result.search_id
        assert_equal 2, result.organic_results.first.position
        assert_equal "https://legacy.example.com", result.organic_results.first.link
      end

      test "uses rank when position is missing" do
        response = FakeResponse.new(
          "200",
          {
            "organic_results" => [
              {
                "rank" => 3,
                "url" => "https://example.com",
                "title" => "Example"
              }
            ]
          }.to_json
        )

        result = with_http_response(response) do
          OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
        end

        assert_equal 3, result.organic_results.first.position
      end

      test "raises on api errors" do
        response = FakeResponse.new("401", { "error" => { "message" => "invalid key", "code" => 401 } }.to_json)

        error = assert_raises(OpenWebNinjaWebSearchClient::Error) do
          with_http_response(response) do
            OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
          end
        end

        assert_includes error.message, "invalid key"
      end

      test "raises on string api errors" do
        response = FakeResponse.new("400", { "error" => "invalid request" }.to_json)

        error = assert_raises(OpenWebNinjaWebSearchClient::Error) do
          with_http_response(response) do
            OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
          end
        end

        assert_includes error.message, "invalid request"
      end

      test "raises on invalid json" do
        response = FakeResponse.new("200", "{")

        error = assert_raises(OpenWebNinjaWebSearchClient::Error) do
          with_http_response(response) do
            OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
          end
        end

        assert_includes error.message, "ungültiges JSON"
      end

      test "raises on http errors" do
        response = FakeResponse.new("500", {}.to_json)

        error = assert_raises(OpenWebNinjaWebSearchClient::Error) do
          with_http_response(response) do
            OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
          end
        end

        assert_includes error.message, "HTTP 500"
      end

      test "raises on network errors" do
        error = assert_raises(OpenWebNinjaWebSearchClient::Error) do
          with_http_error(SocketError.new("failed")) do
            OpenWebNinjaWebSearchClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
          end
        end

        assert_includes error.message, "SocketError"
      end

      test "raises when api key is missing" do
        error = assert_raises(OpenWebNinjaWebSearchClient::Error) do
          OpenWebNinjaWebSearchClient.new(api_key: nil).search(query: "\"Luca Noel\"")
        end

        assert_includes error.message, "OPENWEBNINJA_API_KEY fehlt"
      end

      private

      def with_http_response(response)
        original_start = Net::HTTP.method(:start)
        captured_requests = []

        Net::HTTP.singleton_class.define_method(:start) do |*args, &block|
          if block
            fake_http = Object.new
            fake_http.define_singleton_method(:request) do |request|
              captured_requests << request
              response
            end
            block.call(fake_http)
          else
            response
          end
        end

        result = yield
        @captured_request = captured_requests.last
        result
      ensure
        Net::HTTP.singleton_class.define_method(:start, original_start)
      end

      def with_http_error(error)
        original_start = Net::HTTP.method(:start)

        Net::HTTP.singleton_class.define_method(:start) do |*|
          raise error
        end

        yield
      ensure
        Net::HTTP.singleton_class.define_method(:start, original_start)
      end
    end
  end
end
