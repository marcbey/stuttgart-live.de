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
        assert_equal "\"Luca Noel\" offizielle website", queries.first.query
        assert_equal "\"Luca Noel\" (official OR band OR music OR artist) Instagram site:instagram.com -inurl:/p/ -inurl:/reel/", queries.second.query
        assert_equal "\"Luca Noel\" (official OR band OR music OR artist) site:facebook.com", queries.third.query
        assert_equal "\"Luca Noel\" site:youtube.com/@ OR site:youtube.com/channel", queries.fourth.query
      end

      test "returns no queries when artist name is blank" do
        event = EventStub.new(
          artist_name: "",
          title: "Tour 2026",
          start_at: Time.zone.parse("2026-04-16 20:00:00")
        )

        queries = QueryBuilder.new.call(event:)

        assert_equal [], queries
      end

      test "falls back to title when artist name looks like a quoted tour label" do
        event = EventStub.new(
          artist_name: "„Generation Dating Burnout“ - Lesetour",
          title: "Michael Nast",
          start_at: Time.zone.parse("2026-04-16 20:00:00")
        )

        queries = QueryBuilder.new.call(event:)

        assert_equal "\"Michael Nast\" offizielle website", queries.first.query
        assert_equal "\"Michael Nast\" (official OR band OR music OR artist) Instagram site:instagram.com -inurl:/p/ -inurl:/reel/", queries.second.query
        assert_equal "\"Michael Nast\" (official OR band OR music OR artist) site:facebook.com", queries.third.query
        assert_equal "\"Michael Nast\" site:youtube.com/@ OR site:youtube.com/channel", queries.fourth.query
      end
    end
  end
end
