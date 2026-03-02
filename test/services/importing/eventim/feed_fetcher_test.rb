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
