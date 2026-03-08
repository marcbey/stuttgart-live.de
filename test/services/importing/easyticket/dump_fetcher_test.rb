require "test_helper"

module Importing
  module Easyticket
    class DumpFetcherTest < ActiveSupport::TestCase
      class FakeHttpClient
        attr_reader :last_accept, :requested_urls

        def initialize(responses_by_url)
          @responses_by_url = responses_by_url
          @requested_urls = []
        end

        def get(url, accept: nil)
          @requested_urls << url
          @last_accept = accept
          @responses_by_url.fetch(url)
        end
      end

      test "attaches top-level images index to matching events" do
        client = FakeHttpClient.new(
          "https://dump.example/events?page=1&pageSize=100" => {
            "data" => {
              "event_dates" => [
                { "event_id" => "42", "title_1" => "The Band", "showsoft_location_id" => "7" },
                { "event_id" => "99", "title_1" => "Other Band" }
              ],
              "events" => {
                "42" => {
                  "title_1" => "The Band",
                  "title_2" => "Live"
                }
              },
              "images" => {
                "42" => {
                  "large" => "https://img.example/42-large.jpg",
                  "thumb" => "https://img.example/42-thumb.jpg"
                }
              },
              "locations" => {
                "7" => {
                  "name" => "Im Wizemann",
                  "city" => "Stuttgart"
                }
              }
            },
            "last_page" => 1
          }.to_json
        )

        events = DumpFetcher.new(http_client: client, events_api_url: "https://dump.example/events").fetch_events

        assert_equal "application/json", client.last_accept
        assert_equal [ "https://dump.example/events?page=1&pageSize=100" ], client.requested_urls
        assert_equal(
          {
            "42" => {
              "large" => "https://img.example/42-large.jpg",
              "thumb" => "https://img.example/42-thumb.jpg"
            }
          },
          events.first.dig("data", "images")
        )
        assert_equal "The Band", events.first.dig("data", "event", "title_1")
        assert_equal "Stuttgart", events.first.dig("data", "location", "city")
        assert_nil events.second["data"]
      end

      test "fetches all pages from paginated json api" do
        client = FakeHttpClient.new(
          "https://dump.example/events?page=1&pageSize=2" => {
            "data" => {
              "event_dates" => [
                { "event_id" => "42", "title_1" => "The Band" }
              ],
              "images" => {
                "42" => [
                  { "type" => "large", "url" => "https://img.example/42-large.jpg" }
                ]
              }
            },
            "last_page" => 2
          }.to_json,
          "https://dump.example/events?page=2&pageSize=2" => {
            "data" => {
              "event_dates" => [
                { "event_id" => "99", "title_1" => "Other Band" }
              ],
              "images" => {
                "99" => [
                  { "type" => "large", "url" => "https://img.example/99-large.jpg" }
                ]
              }
            },
            "last_page" => 2
          }.to_json
        )

        events = DumpFetcher.new(
          http_client: client,
          events_api_url: "https://dump.example/events?page=1&pageSize=2"
        ).fetch_events

        assert_equal(
          [
            "https://dump.example/events?page=1&pageSize=2",
            "https://dump.example/events?page=2&pageSize=2"
          ],
          client.requested_urls
        )
        assert_equal [ "42", "99" ], events.map { |event| event["event_id"] }
        assert_equal(
          [ "https://img.example/42-large.jpg", "https://img.example/99-large.jpg" ],
          events.map { |event| event.dig("data", "images", event["event_id"], 0, "url") }
        )
      end
    end
  end
end
