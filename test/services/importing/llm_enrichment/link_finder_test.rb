require "test_helper"

module Importing
  module LlmEnrichment
    class LinkFinderTest < ActiveSupport::TestCase
      EventStub = Struct.new(:id, :artist_name, :title, :venue, :venue_name, :city, :source_snapshot, :start_at, keyword_init: true)

      FakeWebSearchClient = Struct.new(:results_by_query) do
        def search(query:, **)
          results_by_query.fetch(query)
        end
      end

      setup do
        @event = EventStub.new(
          id: 1,
          artist_name: "Luca Noel",
          title: "Tour 2026",
          venue: "Im Wizemann",
          venue_name: "Im Wizemann",
          city: "Stuttgart",
          source_snapshot: {},
          start_at: Time.zone.parse("2026-04-16 20:00:00")
        )
      end

      test "includes top candidates with normalized high-signal fields" do
        result = build_finder(
          {
            "\"Luca Noel\" offizielle website" => search_result(
              "broad-1",
              [
                organic_result(
                  1,
                  "https://www.instagram.com/lucanoelmusik/",
                  "Luca Noel",
                  "www.instagram.com/lucanoelmusik",
                  "Instagram-Snippet",
                  "Instagram",
                  "Profilbeschreibung",
                  [ "de" ],
                  [ "DE" ]
                ),
                organic_result(
                  2,
                  "https://www.lucanoel.de/",
                  "Luca Noel",
                  "www.lucanoel.de",
                  "Offizielle Website",
                  "Website",
                  nil,
                  [],
                  []
                )
              ]
            ),
            "\"Luca Noel\" (official OR band OR music OR artist) Instagram site:instagram.com -inurl:/p/ -inurl:/reel/" => search_result("ig-1", []),
            "\"Luca Noel\" (official OR band OR music OR artist) site:facebook.com" => search_result("fb-1", []),
            "\"Luca Noel\" site:youtube.com/@ OR site:youtube.com/channel" => search_result("yt-1", [])
          }
        ).call(event: @event)

        first_candidate = result.payload.dig("fields", "homepage_link", "candidates", 0)

        assert_equal 4, result.web_search_request_count
        assert_equal 2, result.web_search_candidate_count
        assert_equal "\"Luca Noel\" offizielle website", result.payload.dig("fields", "homepage_link", "query")
        assert_nil result.payload.dig("fields", "venue_external_url")
        assert_equal "https://www.instagram.com/lucanoelmusik/", first_candidate["link"]
        assert_equal "www.instagram.com/lucanoelmusik", first_candidate["displayed_link"]
        assert_equal "Instagram", first_candidate["source"]
        assert_equal "Profilbeschreibung", first_candidate["about_source_description"]
        assert_equal [ "de" ], first_candidate["languages"]
        assert_equal [ "DE" ], first_candidate["regions"]
      end

      test "normalizes instagram candidates" do
        normalized = LinkFinder.normalize_candidate_url(
          "https://secure.instagram.com/lucanoelmusik/?hl=de",
          field_name: :instagram_link
        )

        assert_equal "https://www.instagram.com/lucanoelmusik/", normalized
      end

      test "stores empty field payload when search fails" do
        finder = LinkFinder.new(
          web_search_provider: "serpapi",
          web_search_client: Class.new do
            def search(**)
              raise "kaputt"
            end
          end.new,
          query_builder: QueryBuilder.new
        )

        result = finder.call(event: @event)

        assert_equal [], result.payload.dig("fields", "homepage_link", "candidates")
        assert_equal "RuntimeError", result.payload.dig("fields", "homepage_link", "error_class")
      end

      test "reraises fatal web search errors" do
        finder = LinkFinder.new(
          web_search_provider: "openwebninja",
          web_search_client: Class.new do
            def search(**)
              raise OpenWebNinjaWebSearchClient::AuthenticationError, "Authentication error"
            end
          end.new,
          query_builder: QueryBuilder.new
        )

        assert_raises(OpenWebNinjaWebSearchClient::AuthenticationError) do
          finder.call(event: @event)
        end
      end

      private

      def build_finder(results_by_query)
        LinkFinder.new(
          web_search_provider: "serpapi",
          web_search_client: FakeWebSearchClient.new(results_by_query),
          query_builder: QueryBuilder.new
        )
      end

      def search_result(search_id, organic_results)
        SerpApiClient::SearchResult.new(search_id: search_id, organic_results: organic_results)
      end

      def organic_result(position, link, title, displayed_link, snippet, source, about_source_description, languages, regions)
        SerpApiClient::OrganicResult.new(
          position: position,
          link: link,
          title: title,
          displayed_link: displayed_link,
          snippet: snippet,
          source: source,
          about_source_description: about_source_description,
          languages: languages,
          regions: regions
        )
      end
    end
  end
end
