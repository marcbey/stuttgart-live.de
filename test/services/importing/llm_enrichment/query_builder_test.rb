require "test_helper"

module Importing
  module LlmEnrichment
    class QueryBuilderTest < ActiveSupport::TestCase
      EventStub = Struct.new(:artist_name, :title, :venue, :venue_name, :city, :source_snapshot, :start_at, keyword_init: true)

      test "builds the four web search queries" do
        event = EventStub.new(
          artist_name: "Luca Noel",
          title: "Tour 2026",
          venue: "Im Wizemann",
          venue_name: "Im Wizemann",
          city: "Stuttgart",
          source_snapshot: {},
          start_at: Time.zone.parse("2026-04-16 20:00:00")
        )

        queries = QueryBuilder.new.call(event: event)

        assert_equal [ "broad", "instagram", "facebook", "youtube" ], queries.map(&:name)
        assert_equal "\"Luca Noel\" offizielle website", queries.first.query
        assert_equal "\"Luca Noel\" (official OR band OR music OR artist) Instagram site:instagram.com -inurl:/p/ -inurl:/reel/", queries.second.query
        assert_equal "\"Luca Noel\" (official OR band OR music OR artist) site:facebook.com", queries.third.query
        assert_equal "\"Luca Noel\" site:youtube.com/@ OR site:youtube.com/channel", queries.fourth.query
      end

      test "does not build venue external url queries" do
        event = EventStub.new(
          artist_name: "Luca Noel",
          title: "Tour 2026",
          venue: "Im Wizemann",
          venue_name: "Im Wizemann",
          city: nil,
          source_snapshot: {
            "sources" => [
              { "city" => "Stuttgart", "venue_name" => "Im Wizemann" }
            ]
          },
          start_at: Time.zone.parse("2026-04-16 20:00:00")
        )

        query = QueryBuilder.new.web_search_query(event: event, field_name: :venue_external_url)

        assert_nil query
      end

      test "falls back to title when artist name looks like a quoted tour label" do
        event = EventStub.new(
          artist_name: "„Generation Dating Burnout“ - Lesetour",
          title: "Michael Nast",
          venue: "Theaterhaus",
          venue_name: "Theaterhaus",
          city: "Stuttgart",
          source_snapshot: {},
          start_at: Time.zone.parse("2026-04-16 20:00:00")
        )

        queries = QueryBuilder.new.call(event: event)

        assert_equal "\"Michael Nast\" offizielle website", queries.first.query
        assert_equal "\"Michael Nast\" (official OR band OR music OR artist) Instagram site:instagram.com -inurl:/p/ -inurl:/reel/", queries.second.query
        assert_equal "\"Michael Nast\" (official OR band OR music OR artist) site:facebook.com", queries.third.query
        assert_equal "\"Michael Nast\" site:youtube.com/@ OR site:youtube.com/channel", queries.fourth.query
      end
    end
  end
end
