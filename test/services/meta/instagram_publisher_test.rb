require "test_helper"

class Meta::InstagramPublisherTest < ActiveSupport::TestCase
  test "creates a container and publishes it" do
    client = FakeMetaHttpClient.new(
      { "id" => "container-1" },
      { "id" => "media-1" },
      { "id" => "media-1", "permalink" => "https://www.instagram.com/p/ABC123/" }
    )
    publisher = Meta::InstagramPublisher.new(
      http_client: client,
      instagram_business_account_id: "ig-123",
      page_access_token: "page-token"
    )

    result = publisher.publish!(event_social_post: build_social_post(platform: "instagram"))

    assert_equal "https://graph.facebook.com/v25.0/ig-123/media", client.calls.first.fetch(:url)
    assert_equal "https://graph.facebook.com/v25.0/ig-123/media_publish", client.calls.second.fetch(:url)
    assert_equal "https://graph.facebook.com/v25.0/media-1", client.calls.third.fetch(:url)
    assert_equal "container-1", client.calls.second.fetch(:params).fetch(:creation_id)
    assert_equal "media-1", result.remote_media_id
    assert_nil result.remote_post_id
    assert_equal "https://www.instagram.com/p/ABC123/", result.payload.dig("media", "permalink")
  end

  private

  def build_social_post(platform:)
    EventSocialPost.new(
      event: events(:published_one),
      platform:,
      status: "approved",
      caption: "Caption",
      target_url: "https://example.com/events/published-event",
      image_url: "https://example.com/published.jpg",
      approved_at: Time.current
    )
  end

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
