require "test_helper"

module Importing
  module LlmEnrichment
    class SerpApiClientTest < ActiveSupport::TestCase
      FakeResponse = Struct.new(:code, :body) do
        def is_a?(klass)
          klass == Net::HTTPSuccess ? code.to_s.start_with?("2") : super
        end
      end

      test "returns parsed organic results" do
        response = FakeResponse.new(
          "200",
          {
            "search_metadata" => { "id" => "search-123" },
            "organic_results" => [
              {
                "position" => 1,
                "link" => "https://example.com",
                "title" => "Example",
                "snippet" => "Snippet"
              }
            ]
          }.to_json
        )

        result = with_http_response(response) do
          SerpApiClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
        end

        assert_equal "search-123", result.search_id
        assert_equal "https://example.com", result.organic_results.first.link
        assert_equal "", result.organic_results.first.displayed_link
        assert_equal "", result.organic_results.first.source
      end

      test "raises on api errors" do
        response = FakeResponse.new("200", { "error" => "invalid key" }.to_json)

        error = assert_raises(SerpApiClient::Error) do
          with_http_response(response) do
            SerpApiClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
          end
        end

        assert_includes error.message, "invalid key"
      end

      test "raises on invalid json" do
        response = FakeResponse.new("200", "{")

        error = assert_raises(SerpApiClient::Error) do
          with_http_response(response) do
            SerpApiClient.new(api_key: "secret").search(query: "\"Luca Noel\"")
          end
        end

        assert_includes error.message, "ungültiges JSON"
      end

      test "raises when api key is missing" do
        error = assert_raises(SerpApiClient::Error) do
          SerpApiClient.new(api_key: nil).search(query: "\"Luca Noel\"")
        end

        assert_includes error.message, "SERPAPI_API_KEY fehlt"
      end

      private

      def with_http_response(response)
        original_start = Net::HTTP.method(:start)

        Net::HTTP.singleton_class.define_method(:start) do |*args, &block|
          if block
            fake_http = Object.new
            fake_http.define_singleton_method(:request) { |_request| response }
            block.call(fake_http)
          else
            response
          end
        end

        yield
      ensure
        Net::HTTP.singleton_class.define_method(:start, original_start)
      end
    end
  end
end
