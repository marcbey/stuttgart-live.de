require "test_helper"

class Meta::FacebookImageRelayTest < ActiveSupport::TestCase
  test "uploads an unpublished page photo and returns the facebook cdn source" do
    client = FakeMetaHttpClient.new(
      { "id" => "photo-1" },
      { "images" => [ { "source" => "https://scontent.example.com/photo.jpg" } ] }
    )
    relay = Meta::FacebookImageRelay.new(
      http_client: client,
      page_id: "page-123",
      page_access_token: "page-token"
    )

    url = relay.relay_image_url(source_url: "https://example.com/source.jpg")

    assert_equal "https://scontent.example.com/photo.jpg", url
    assert_equal "https://graph.facebook.com/v25.0/page-123/photos", client.calls.first.fetch(:url)
    assert_equal false, client.calls.first.fetch(:params).fetch(:published)
    assert_equal "https://example.com/source.jpg", client.calls.first.fetch(:params).fetch(:url)
    assert_equal "https://graph.facebook.com/v25.0/photo-1", client.calls.second.fetch(:url)
    assert_equal "images", client.calls.second.fetch(:params).fetch(:fields)
  end

  test "returns nil when no facebook page is available" do
    relay = Meta::FacebookImageRelay.new(
      http_client: FakeMetaHttpClient.new,
      page_id: nil,
      page_access_token: nil
    )

    assert_nil relay.relay_image_url(source_url: "https://example.com/source.jpg")
  end

  private

  class FakeMetaHttpClient
    attr_reader :calls

    def initialize(*responses)
      @responses = responses
      @calls = []
    end

    def post_form!(url, params:)
      calls << { url:, params: params.deep_dup }
      @responses.shift
    end

    def get_json!(url, params: {})
      calls << { url:, params: params.deep_dup }
      @responses.shift
    end
  end
end
