require "test_helper"
require "stringio"
require "zlib"

module Importing
  module Eventim
    class FeedFetcherTest < ActiveSupport::TestCase
      class FakeHttpClient
        attr_reader :last_accept

        def initialize(response_body)
          @response_body = response_body
        end

        def get(_url, accept: nil)
          @last_accept = accept
          @response_body
        end
      end

      test "parses gzipped xml feeds" do
        xml = <<~XML
          <root>
            <event>
              <eventId>evt-1</eventId>
              <date>2026-06-17</date>
            </event>
            <event>
              <eventId>evt-2</eventId>
              <date>2026-06-18</date>
            </event>
          </root>
        XML
        gzipped = gzip(xml)

        client = FakeHttpClient.new(gzipped)
        events = FeedFetcher.new(http_client: client, feed_url: "https://example.test/feed.xml.gz").fetch_events

        assert_equal 2, events.size
        assert_equal "evt-1", events.first["eventId"]
        assert_equal "application/xml,text/xml", client.last_accept
      end

      test "raises request error for status info response" do
        xml = <<~XML
          <StatusInfo>
            <code>401</code>
            <description>Unauthorized</description>
          </StatusInfo>
        XML
        client = FakeHttpClient.new(xml)

        assert_raises(RequestError) do
          FeedFetcher.new(http_client: client, feed_url: "https://example.test/feed.xml").fetch_events
        end
      end

      test "streams rows via block without building result array" do
        xml = <<~XML
          <root>
            <event><eventId>evt-1</eventId><date>2026-06-17</date></event>
            <event><eventId>evt-2</eventId><date>2026-06-18</date></event>
          </root>
        XML
        client = FakeHttpClient.new(gzip(xml))
        yielded = []

        returned = FeedFetcher.new(http_client: client, feed_url: "https://example.test/feed.xml.gz").fetch_events do |row|
          yielded << row["eventId"]
        end

        assert_equal [], returned
        assert_equal [ "evt-1", "evt-2" ], yielded
      end

      test "includes xml attributes in parsed payload" do
        xml = <<~XML
          <root>
            <event eventid="evt-9" espicture_big="https://img.example/evt-9-big.jpg" artistImage="https://img.example/evt-9-artist.jpg">
              <eventdate>2026-06-17</eventdate>
              <pricecategory currency="EUR">
                <price>49.90</price>
              </pricecategory>
            </event>
          </root>
        XML

        client = FakeHttpClient.new(gzip(xml))
        events = FeedFetcher.new(http_client: client, feed_url: "https://example.test/feed.xml.gz").fetch_events
        row = events.first

        assert_equal "evt-9", row["eventid"]
        assert_equal "https://img.example/evt-9-big.jpg", row["espicture_big"]
        assert_equal "https://img.example/evt-9-artist.jpg", row["artistImage"]
        assert_equal "EUR", row.dig("pricecategory", "currency")
      end

      test "expands eventserie rows and inherits series image fields" do
        xml = <<~XML
          <root>
            <eventserie>
              <artist>
                <artistImage>https://img.example/artist.jpg</artistImage>
              </artist>
              <espicture_big>https://img.example/series-big.jpg</espicture_big>
              <event>
                <eventid>evt-11</eventid>
                <eventdate>2026-08-10</eventdate>
                <eventplace>Stuttgart</eventplace>
                <eventvenue>Im Wizemann</eventvenue>
              </event>
              <event>
                <eventid>evt-12</eventid>
                <eventdate>2026-08-11</eventdate>
                <eventplace>Stuttgart</eventplace>
                <eventvenue>LKA</eventvenue>
              </event>
            </eventserie>
          </root>
        XML

        client = FakeHttpClient.new(gzip(xml))
        events = FeedFetcher.new(http_client: client, feed_url: "https://example.test/feed.xml.gz").fetch_events

        assert_equal 2, events.size
        assert_equal [ "evt-11", "evt-12" ], events.map { |row| row["eventid"] }
        assert_equal "https://img.example/series-big.jpg", events.first["espicture_big"]
        assert_equal "https://img.example/artist.jpg", events.first.dig("artist", "artistImage")
      end

      private

      def gzip(content)
        io = StringIO.new
        writer = Zlib::GzipWriter.new(io)
        writer.write(content)
        writer.close
        io.string
      end
    end
  end
end
