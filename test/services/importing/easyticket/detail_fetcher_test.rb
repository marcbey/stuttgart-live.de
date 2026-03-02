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
          event_detail_api: "https://api.example.test/events/%{event_id}?shop=%{partner_shop_id}&api_key=%{api_key}",
          api_key: "secret",
          partner_shop_id: "shop-42"
        )

        payload = fetcher.fetch("123")

        assert_equal "application/json", client.last_accept
        assert_equal "https://api.example.test/events/123?shop=shop-42&api_key=secret", client.last_url
        assert_equal "X", payload.dig("data", "event", "title")
      end

      test "formats braces placeholders used in env files" do
        client = FakeHttpClient.new('{"data":{"event":{"title":"X"}}}')
        fetcher = DetailFetcher.new(
          http_client: client,
          event_detail_api: "https://api.example.test/events/{event_id}?shop={partner_shop_id}",
          api_key: "secret",
          partner_shop_id: "shop-42"
        )

        fetcher.fetch("123")

        assert_equal "https://api.example.test/events/123?shop=shop-42&api_key=secret", client.last_url
      end

      test "appends api_key query param when api_key missing in url" do
        client = FakeHttpClient.new('{"data":{}}')
        fetcher = DetailFetcher.new(
          http_client: client,
          event_detail_api: "https://api.example.test/events",
          api_key: "secret"
        )

        fetcher.fetch("99")

        assert_equal "https://api.example.test/events/99?api_key=secret", client.last_url
      end

      test "raises error for unsupported placeholders" do
        client = FakeHttpClient.new('{"data":{}}')
        fetcher = DetailFetcher.new(
          http_client: client,
          event_detail_api: "https://api.example.test/events/%{foo}",
          api_key: "secret"
        )

        assert_raises(Error) { fetcher.fetch("99") }
      end

      test "raises error for unsupported braces placeholders" do
        client = FakeHttpClient.new('{"data":{}}')
        fetcher = DetailFetcher.new(
          http_client: client,
          event_detail_api: "https://api.example.test/events/{foo}",
          api_key: "secret"
        )

        assert_raises(Error) { fetcher.fetch("99") }
      end
    end
  end
end
