require "test_helper"

module Importing
  module LlmEnrichment
    class LinkFinderTest < ActiveSupport::TestCase
      EventStub = Struct.new(:id, :artist_name, :title, :venue, :start_at, keyword_init: true)

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
          start_at: Time.zone.parse("2026-04-16 20:00:00")
        )
      end

      test "uses the first homepage result without extra checks" do
        result = build_finder(
          {
            "\"Luca Noel\" offizielle website" => search_result(
              "broad-1",
              [
                organic_result(1, "https://www.instagram.com/lucanoelmusik/", "Instagram", "Social"),
                organic_result(2, "https://www.lucanoel.de/", "Luca Noel", "Offizielle Website")
              ]
            )
          }
        ).call(event: @event)

        assert_equal "https://www.instagram.com/lucanoelmusik/", result.links[:homepage_link]
        assert_equal "\"Luca Noel\" offizielle website", result.payload.dig("fields", "homepage_link", "query")
        assert_equal "https://www.instagram.com/lucanoelmusik/", result.payload.dig("fields", "homepage_link", "selected_url")
        assert_equal "first_search_result", result.payload.dig("fields", "homepage_link", "candidates", 0, "selection_strategy")
      end

      test "uses the first social result without validation" do
        result = build_finder(
          {
            "\"Luca Noel\" offizielle website" => search_result("broad-1", []),
            "\"Luca Noel\" (official OR band OR music OR artist) Instagram site:instagram.com -inurl:/p/ -inurl:/reel/" => search_result("ig-1", [ organic_result(1, "https://secure.instagram.com/lucanoelmusik/?hl=da", "Luca Noel", "Instagram") ]),
            "\"Luca Noel\" official page site:facebook.com" => search_result("fb-1", [ organic_result(1, "https://www.facebook.com/lucanoelmusik/", "Luca Noel", "Facebook") ]),
            "\"Luca Noel\" site:youtube.com/@ OR site:youtube.com/channel" => search_result("yt-1", [])
          }
        ).call(event: @event)

        assert_equal "https://www.instagram.com/lucanoelmusik/", result.links[:instagram_link]
        assert_equal "https://www.facebook.com/lucanoelmusik/", result.links[:facebook_link]
        assert_equal "\"Luca Noel\" (official OR band OR music OR artist) Instagram site:instagram.com -inurl:/p/ -inurl:/reel/", result.payload.dig("fields", "instagram_link", "query")
        assert_equal "\"Luca Noel\" official page site:facebook.com", result.payload.dig("fields", "facebook_link", "query")
        assert_equal "first_search_result", result.payload.dig("fields", "instagram_link", "candidates", 0, "selection_strategy")
        assert_equal "first_search_result", result.payload.dig("fields", "facebook_link", "candidates", 0, "selection_strategy")
      end

      test "selects all links via web search" do
        result = build_finder(
          {
            "\"Luca Noel\" offizielle website" => search_result("broad-1", [ organic_result(1, "https://www.lucanoel.de/", "Luca Noel", "Offizielle Website") ]),
            "\"Luca Noel\" (official OR band OR music OR artist) Instagram site:instagram.com -inurl:/p/ -inurl:/reel/" => search_result("ig-1", [ organic_result(1, "https://www.instagram.com/lucanoelmusik/", "Luca Noel", "Instagram") ]),
            "\"Luca Noel\" official page site:facebook.com" => search_result("fb-1", [ organic_result(1, "https://www.facebook.com/lucanoelmusik/", "Luca Noel", "Facebook") ]),
            "\"Luca Noel\" site:youtube.com/@ OR site:youtube.com/channel" => search_result("yt-1", [ organic_result(1, "https://www.youtube.com/@lucanoelmusic", "Luca Noel", "YouTube") ])
          }
        ).call(event: @event)

        assert_equal "https://www.lucanoel.de/", result.links[:homepage_link]
        assert_equal "https://www.instagram.com/lucanoelmusik/", result.links[:instagram_link]
        assert_equal "https://www.facebook.com/lucanoelmusik/", result.links[:facebook_link]
        assert_equal "https://www.youtube.com/@lucanoelmusic", result.links[:youtube_link]
        assert_equal 4, result.links_found_via_web_search_count
        assert_equal 4, result.web_search_request_count
      end

      test "uses the first youtube result even when it is a video page" do
        event = EventStub.new(
          id: 2,
          artist_name: "Café del Mundo",
          title: "GuitaRevolution",
          venue: "Theaterhaus",
          start_at: Time.zone.parse("2026-03-25 20:00:00")
        )

        result = build_finder(
          {
            "\"Café del Mundo\" offizielle website" => search_result("broad-1", []),
            "\"Café del Mundo\" (official OR band OR music OR artist) Instagram site:instagram.com -inurl:/p/ -inurl:/reel/" => search_result("ig-1", []),
            "\"Café del Mundo\" official page site:facebook.com" => search_result("fb-1", []),
            "\"Café del Mundo\" site:youtube.com/@ OR site:youtube.com/channel" => search_result(
              "yt-1",
              [
                organic_result(1, "https://www.youtube.com/watch?v=abc123", "Video", "Video"),
                organic_result(2, "https://www.youtube.com/@CafedelMundoGuitars", "Café del Mundo", "Channel")
              ]
            )
          }
        ).call(event: event)

        assert_equal "https://www.youtube.com/watch?v=abc123", result.links[:youtube_link]
        assert_equal "first_search_result", result.payload.dig("fields", "youtube_link", "candidates", 0, "selection_strategy")
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

      def organic_result(position, link, title, snippet)
        SerpApiClient::OrganicResult.new(position: position, link: link, title: title, snippet: snippet)
      end
    end
  end
end
