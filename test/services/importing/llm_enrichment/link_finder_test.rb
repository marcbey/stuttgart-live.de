require "test_helper"

module Importing
  module LlmEnrichment
    class LinkFinderTest < ActiveSupport::TestCase
      EventStub = Struct.new(:id, :artist_name, :title, :venue, :start_at, keyword_init: true)

      FakeSerpApiClient = Struct.new(:results_by_query) do
        def search(query:, **)
          results_by_query.fetch(query)
        end
      end

      FakeLinkValidator = Struct.new(:results_by_url) do
        def call(url:, field_name:)
          results_by_url.fetch([ field_name.to_sym, url ]) do
            Importing::LlmEnrichment::LinkValidator::Result.new(
              accepted: true,
              sanitized_url: url,
              status: "ok",
              final_url: url,
              http_status: 200,
              error_class: nil,
              matched_phrase: nil,
              checked_at: Time.current
            )
          end
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

      test "selects the official homepage from broad results" do
        result = build_finder(
          {
            "\"Luca Noel\"" => search_result(
              "broad-1",
              [
                organic_result(1, "https://www.instagram.com/lucanoelmusik/", "Instagram", "Social"),
                organic_result(2, "https://www.lucanoel.de/", "Luca Noel", "Offizielle Website")
              ]
            ),
            "\"Luca Noel\" site:instagram.com" => search_result("ig-1", []),
            "\"Luca Noel\" site:facebook.com" => search_result("fb-1", []),
            "\"Luca Noel\" site:youtube.com" => search_result("yt-1", [])
          }
        ).call(event: @event)

        assert_equal "https://www.lucanoel.de/", result.links[:homepage_link]
        assert_equal "https://www.lucanoel.de/", result.payload.dig("fields", "homepage_link", "selected_url")
        assert_equal "blocked_homepage_domain", result.payload.dig("fields", "homepage_link", "candidates", 1, "rejection_reason")
      end

      test "selects social profile matches without http validation" do
        validator = Class.new do
          def call(url:, field_name:)
            raise "social profiles should not be HTTP-validated" if %i[instagram_link facebook_link].include?(field_name.to_sym)

            Importing::LlmEnrichment::LinkValidator::Result.new(
              accepted: true,
              sanitized_url: url,
              status: "ok",
              final_url: url,
              http_status: 200,
              error_class: nil,
              matched_phrase: nil,
              checked_at: Time.current
            )
          end
        end.new

        result = build_finder(
          {
            "\"Luca Noel\"" => search_result("broad-1", []),
            "\"Luca Noel\" site:instagram.com" => search_result("ig-1", [ organic_result(1, "https://www.instagram.com/lucanoelmusik/", "Luca Noel", "Instagram") ]),
            "\"Luca Noel\" site:facebook.com" => search_result("fb-1", [ organic_result(1, "https://www.facebook.com/lucanoelmusik/", "Luca Noel", "Facebook") ]),
            "\"Luca Noel\" site:youtube.com" => search_result("yt-1", [])
          },
          link_validator: validator
        ).call(event: @event)

        assert_equal "https://www.instagram.com/lucanoelmusik/", result.links[:instagram_link]
        assert_equal "https://www.facebook.com/lucanoelmusik/", result.links[:facebook_link]
        assert_equal "search_profile_match", result.payload.dig("fields", "instagram_link", "candidates", 0, "selection_strategy")
        assert_equal "search_profile_match", result.payload.dig("fields", "facebook_link", "candidates", 0, "selection_strategy")
        assert_nil result.payload.dig("fields", "instagram_link", "candidates", 0, "validation")
        assert_nil result.payload.dig("fields", "facebook_link", "candidates", 0, "validation")
      end

      test "rejects youtube video pages and invalid channels" do
        event = EventStub.new(
          id: 2,
          artist_name: "Café del Mundo",
          title: "GuitaRevolution",
          venue: "Theaterhaus",
          start_at: Time.zone.parse("2026-03-25 20:00:00")
        )
        validator = FakeLinkValidator.new(
          {
            [ :youtube_link, "https://www.youtube.com/@CafedelMundoGuitars" ] => Importing::LlmEnrichment::LinkValidator::Result.new(
              accepted: false,
              sanitized_url: nil,
              status: "rejected_http_error",
              final_url: "https://www.youtube.com/@CafedelMundoGuitars",
              http_status: 404,
              error_class: nil,
              matched_phrase: nil,
              checked_at: Time.current
            )
          }
        )

        result = build_finder(
          {
            "\"Café del Mundo\"" => search_result("broad-1", []),
            "\"Café del Mundo\" site:instagram.com" => search_result("ig-1", []),
            "\"Café del Mundo\" site:facebook.com" => search_result("fb-1", []),
            "\"Café del Mundo\" site:youtube.com" => search_result(
              "yt-1",
              [
                organic_result(1, "https://www.youtube.com/watch?v=abc123", "Video", "Video"),
                organic_result(2, "https://www.youtube.com/@CafedelMundoGuitars", "Café del Mundo", "Channel")
              ]
            )
          },
          link_validator: validator
        ).call(event: event)

        assert_nil result.links[:youtube_link]
        assert_equal "rejected_http_error", result.payload.dig("fields", "youtube_link", "candidates", 0, "rejection_reason")
        assert_equal "non_channel_path", result.payload.dig("fields", "youtube_link", "candidates", 1, "rejection_reason")
      end

      private

      def build_finder(results_by_query, link_validator: FakeLinkValidator.new({}))
        LinkFinder.new(
          serpapi_client: FakeSerpApiClient.new(results_by_query),
          query_builder: QueryBuilder.new,
          link_validator: link_validator
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
