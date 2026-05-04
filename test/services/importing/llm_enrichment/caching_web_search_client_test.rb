require "test_helper"

module Importing
  module LlmEnrichment
    class CachingWebSearchClientTest < ActiveSupport::TestCase
      FakeClient = Struct.new(:result, :error, :calls, keyword_init: true) do
        def search(**params)
          calls << params
          raise error if error

          result
        end
      end

      setup do
        @cache = ActiveSupport::Cache::MemoryStore.new
      end

      test "caches identical successful searches" do
        fake_client = fake_client_with_result(search_result("search-1", [ organic_result(1, "https://example.com") ]))
        client = build_client(client: fake_client)

        first_result = client.search(query: "  Luca   Noel  ", num: 10)
        second_result = client.search(query: "Luca Noel", num: 10)

        assert_equal 1, fake_client.calls.size
        assert_equal "search-1", first_result.search_id
        assert_equal "search-1", second_result.search_id
        assert_equal "https://example.com", second_result.organic_results.first.link
      end

      test "keeps separate cache entries for provider and search parameters" do
        serpapi_client = fake_client_with_result(search_result("serpapi-search", []))
        openwebninja_client = fake_client_with_result(search_result("openwebninja-search", []))
        serpapi = build_client(provider: "serpapi", client: serpapi_client)
        openwebninja = build_client(provider: "openwebninja", client: openwebninja_client)

        serpapi.search(query: "Luca Noel", num: 10, hl: "de", device: "desktop")
        serpapi.search(query: "Luca Noel", num: 5, hl: "de", device: "desktop")
        serpapi.search(query: "Luca Noel", num: 10, hl: "en", device: "desktop")
        serpapi.search(query: "Luca Noel", num: 10, hl: "de", device: "mobile")
        openwebninja.search(query: "Luca Noel", num: 10, hl: "de", device: "desktop")

        assert_equal 4, serpapi_client.calls.size
        assert_equal 1, openwebninja_client.calls.size
      end

      test "caches empty successful results" do
        fake_client = fake_client_with_result(search_result("empty-search", []))
        client = build_client(client: fake_client)

        first_result = client.search(query: "Luca Noel")
        second_result = client.search(query: "Luca Noel")

        assert_equal 1, fake_client.calls.size
        assert_equal [], first_result.organic_results
        assert_equal [], second_result.organic_results
      end

      test "does not cache exceptions" do
        fake_client = fake_client_with_error(StandardError.new("kaputt"))
        client = build_client(client: fake_client)

        assert_raises(StandardError) { client.search(query: "Luca Noel") }
        assert_raises(StandardError) { client.search(query: "Luca Noel") }

        assert_equal 2, fake_client.calls.size
      end

      test "bypasses cache when no_cache is true" do
        fake_client = fake_client_with_result(search_result("fresh-search", []))
        client = build_client(client: fake_client)

        client.search(query: "Luca Noel", no_cache: true)
        client.search(query: "Luca Noel", no_cache: true)

        assert_equal 2, fake_client.calls.size
        assert_equal [ true, true ], fake_client.calls.map { |call| call.fetch(:no_cache) }
      end

      test "deserializes cached results into web search response objects" do
        fake_client = fake_client_with_result(
          search_result(
            "search-1",
            [
              organic_result(
                1,
                "https://example.com",
                title: "Example",
                displayed_link: "example.com",
                snippet: "Snippet",
                source: "Website",
                about_source_description: "Beschreibung",
                languages: [ "de" ],
                regions: [ "DE" ]
              )
            ]
          )
        )
        client = build_client(client: fake_client)

        client.search(query: "Luca Noel")
        cached_result = client.search(query: "Luca Noel")

        assert_instance_of WebSearchResponse::SearchResult, cached_result
        assert_instance_of WebSearchResponse::OrganicResult, cached_result.organic_results.first
        assert_equal "search-1", cached_result.search_id
        assert_equal "Example", cached_result.organic_results.first.title
        assert_equal [ "de" ], cached_result.organic_results.first.languages
        assert_equal [ "DE" ], cached_result.organic_results.first.regions
      end

      private

      def build_client(provider: "serpapi", client:)
        CachingWebSearchClient.new(provider:, client:, cache: @cache)
      end

      def fake_client_with_result(result)
        FakeClient.new(result:, calls: [])
      end

      def fake_client_with_error(error)
        FakeClient.new(error:, calls: [])
      end

      def search_result(search_id, organic_results)
        WebSearchResponse::SearchResult.new(search_id:, organic_results:)
      end

      def organic_result(
        position,
        link,
        title: "",
        displayed_link: "",
        snippet: "",
        source: "",
        about_source_description: "",
        languages: [],
        regions: []
      )
        WebSearchResponse::OrganicResult.new(
          position:,
          link:,
          title:,
          displayed_link:,
          snippet:,
          source:,
          about_source_description:,
          languages:,
          regions:
        )
      end
    end
  end
end
