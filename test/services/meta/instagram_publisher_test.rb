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
      instagram_account_id: "ig-123",
      user_access_token: "ig-user-token"
    )

    result = publisher.publish!(event_social_post: build_social_post(platform: "instagram"))

    assert_equal "https://graph.instagram.com/v25.0/ig-123/media", client.calls.first.fetch(:url)
    assert_equal "https://graph.instagram.com/v25.0/ig-123/media_publish", client.calls.second.fetch(:url)
    assert_equal "https://graph.instagram.com/v25.0/media-1", client.calls.third.fetch(:url)
    assert_equal "container-1", client.calls.second.fetch(:params).fetch(:creation_id)
    assert_equal "media-1", result.remote_media_id
    assert_nil result.remote_post_id
    assert_equal "https://www.instagram.com/p/ABC123/", result.payload.dig("media", "permalink")
  end

  test "includes container status when publish returns no media id" do
    client = FakeMetaHttpClient.new(
      { "id" => "container-1" },
      {},
      { "id" => "container-1", "status_code" => "ERROR" }
    )
    publisher = Meta::InstagramPublisher.new(
      http_client: client,
      instagram_account_id: "ig-123",
      user_access_token: "ig-user-token"
    )

    error = assert_raises(Meta::Error) do
      publisher.publish!(event_social_post: build_social_post(platform: "instagram"))
    end

    assert_equal "Instagram hat keine Media-ID zurückgegeben (Container-Status: ERROR).", error.message
    assert_equal "https://graph.instagram.com/v25.0/container-1", client.calls.third.fetch(:url)
    assert_equal "id,status_code", client.calls.third.fetch(:params).fetch(:fields)
  end

  private

  def build_social_post(platform:)
    EventSocialPost.new(
      event: events(:published_one),
      platform:,
      status: "draft",
      caption: "Caption",
      target_url: "https://example.com/events/published-event",
      image_url: "https://example.com/published.jpg"
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
