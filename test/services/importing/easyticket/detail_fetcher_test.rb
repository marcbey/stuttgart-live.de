require "test_helper"

module Importing
  module Easyticket
    class DetailFetcherTest < ActiveSupport::TestCase
      class FakeHttpClient
        attr_reader :last_url, :last_accept

        def initialize(response_body)
          @response_body = response_body
        end

        def get(url, accept: nil)
          @last_url = url
          @last_accept = accept
          @response_body
        end
      end

      test "formats url placeholders including partner shop id" do
        client = FakeHttpClient.new('{"data":{"event":{"title":"X"}}}')
        fetcher = DetailFetcher.new(
          http_client: client,
          event_detail_api: "https://api.example.test/events/%{event_id}?shop=%{partner_shop_id}",
          partner_shop_id: "shop-42"
        )

        payload = fetcher.fetch("123")

        assert_equal "application/json", client.last_accept
        assert_equal "https://api.example.test/events/123?shop=shop-42", client.last_url
        assert_equal "X", payload.dig("data", "event", "title")
      end

      test "appends event id to base url when no placeholder is present" do
        client = FakeHttpClient.new('{"data":{}}')
        fetcher = DetailFetcher.new(
          http_client: client,
          event_detail_api: "https://api.example.test/events"
        )

        fetcher.fetch("99")

        assert_equal "https://api.example.test/events/99", client.last_url
      end
    end
  end
end
