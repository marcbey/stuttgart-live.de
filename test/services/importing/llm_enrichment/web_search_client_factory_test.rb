require "test_helper"

module Importing
  module LlmEnrichment
    class WebSearchClientFactoryTest < ActiveSupport::TestCase
      test "wraps serpapi client with cache" do
        client = WebSearchClientFactory.build(provider: "serpapi")

        assert_instance_of CachingWebSearchClient, client
        assert_equal "serpapi", client.provider
        assert_instance_of SerpApiClient, client.client
      end

      test "wraps openwebninja client with cache" do
        client = WebSearchClientFactory.build(provider: "openwebninja")

        assert_instance_of CachingWebSearchClient, client
        assert_equal "openwebninja", client.provider
        assert_instance_of OpenWebNinjaWebSearchClient, client.client
      end
    end
  end
end
