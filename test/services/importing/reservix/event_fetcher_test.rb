require "test_helper"

module Importing
  module Reservix
    class EventFetcherTest < ActiveSupport::TestCase
      class FakeHttpClient
        attr_reader :requested_urls

        def initialize(response_body)
          @response_body = response_body
          @requested_urls = []
        end

        def get(url)
          @requested_urls << url
          @response_body
        end
      end

      test "stops before request when stop was requested" do
        client = FakeHttpClient.new({ "data" => [] }.to_json)

        assert_raises(Importing::StopRequested) do
          EventFetcher.new(http_client: client).fetch_pages(stop_requested: -> { true }) { |_events, **| }
        end

        assert_equal [], client.requested_urls
      end
    end
  end
end
