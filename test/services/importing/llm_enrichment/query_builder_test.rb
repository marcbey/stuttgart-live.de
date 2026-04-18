require "test_helper"

module Importing
  module LlmEnrichment
    class QueryBuilderTest < ActiveSupport::TestCase
      EventStub = Struct.new(:artist_name, :title, :start_at, keyword_init: true)

      test "builds the four web search queries" do
        event = EventStub.new(
          artist_name: "Luca Noel",
          title: "Tour 2026",
          start_at: Time.zone.parse("2026-04-16 20:00:00")
        )

        queries = QueryBuilder.new.call(event: event)

        assert_equal [ "broad", "instagram", "facebook", "youtube" ], queries.map(&:name)
        assert_equal "\"Luca Noel\"", queries.first.query
        assert_equal "\"Luca Noel\" site:instagram.com", queries.second.query
        assert_equal "\"Luca Noel\" site:facebook.com", queries.third.query
        assert_equal "\"Luca Noel\" site:youtube.com", queries.fourth.query
      end
    end
  end
end
