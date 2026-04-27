require "test_helper"

class Meta::InstagramPublisherTest < ActiveSupport::TestCase
  test "creates a container and publishes it" do
    client = FakeMetaHttpClient.new(
      { "id" => "container-1" },
      { "id" => "container-1", "status_code" => "FINISHED" },
      { "id" => "media-1" },
      { "id" => "media-1", "permalink" => "https://www.instagram.com/p/ABC123/" }
    )
    publisher = Meta::InstagramPublisher.new(
      http_client: client,
      instagram_account_id: "ig-123",
      user_access_token: "ig-user-token",
      image_relay: nil
    )

    result = publisher.publish!(event_social_post: build_social_post(platform: "instagram"))

    assert_equal "https://graph.instagram.com/v25.0/ig-123/media", client.calls.first.fetch(:url)
    assert_not_includes client.calls.first.fetch(:params), :media_type
    assert_equal "https://example.com/published.jpg", client.calls.first.fetch(:params).fetch(:image_url)
    assert_equal "https://graph.instagram.com/v25.0/container-1", client.calls.second.fetch(:url)
    assert_equal "https://graph.instagram.com/v25.0/ig-123/media_publish", client.calls.third.fetch(:url)
    assert_equal "https://graph.instagram.com/v25.0/media-1", client.calls.fourth.fetch(:url)
    assert_equal "container-1", client.calls.third.fetch(:params).fetch(:creation_id)
    assert_equal "media-1", result.remote_media_id
    assert_nil result.remote_post_id
    assert_equal "FINISHED", result.payload.dig("container_status", "status_code")
    assert_equal "https://www.instagram.com/p/ABC123/", result.payload.dig("media", "permalink")
  end

  test "uses relayed facebook cdn image urls when available" do
    client = FakeMetaHttpClient.new(
      { "id" => "container-1" },
      { "id" => "container-1", "status_code" => "FINISHED" },
      { "id" => "media-1" },
      { "id" => "media-1", "permalink" => "https://www.instagram.com/p/ABC123/" }
    )
    relay = FakeImageRelay.new("https://scontent.example.com/relayed.jpg")
    publisher = Meta::InstagramPublisher.new(
      http_client: client,
      instagram_account_id: "ig-123",
      user_access_token: "ig-user-token",
      image_relay: relay
    )

    publisher.publish!(event_social_post: build_social_post(platform: "instagram"))

    assert_equal [ "https://example.com/published.jpg" ], relay.source_urls
    assert_equal "https://scontent.example.com/relayed.jpg", client.calls.first.fetch(:params).fetch(:image_url)
  end

  test "raises a specific error when image relay fails" do
    client = FakeMetaHttpClient.new
    relay = FailingImageRelay.new("Facebook upload failed")
    publisher = Meta::InstagramPublisher.new(
      http_client: client,
      instagram_account_id: "ig-123",
      user_access_token: "ig-user-token",
      image_relay: relay
    )

    error = assert_raises(Meta::Error) do
      publisher.publish!(event_social_post: build_social_post(platform: "instagram"))
    end

    assert_equal "Instagram-Bild konnte nicht über Facebook-CDN vorbereitet werden: Facebook upload failed", error.message
    assert_empty client.calls
  end

  test "includes container status when publish returns no media id" do
    client = FakeMetaHttpClient.new(
      { "id" => "container-1" },
      { "id" => "container-1", "status_code" => "FINISHED" },
      {},
      { "id" => "container-1", "status_code" => "ERROR" }
    )
    publisher = Meta::InstagramPublisher.new(
      http_client: client,
      instagram_account_id: "ig-123",
      user_access_token: "ig-user-token",
      image_relay: nil
    )

    error = assert_raises(Meta::Error) do
      publisher.publish!(event_social_post: build_social_post(platform: "instagram"))
    end

    assert_equal "Instagram hat keine Media-ID zurückgegeben (Container-Status: ERROR).", error.message
    assert_equal "https://graph.instagram.com/v25.0/container-1", client.calls.fourth.fetch(:url)
    assert_equal "id,status_code", client.calls.fourth.fetch(:params).fetch(:fields)
  end

  test "waits until the container is finished before publishing" do
    client = FakeMetaHttpClient.new(
      { "id" => "container-1" },
      { "id" => "container-1", "status_code" => "IN_PROGRESS" },
      { "id" => "container-1", "status_code" => "FINISHED" },
      { "id" => "media-1" },
      { "id" => "media-1", "permalink" => "https://www.instagram.com/p/ABC123/" }
    )
    sleeps = []
    publisher = Meta::InstagramPublisher.new(
      http_client: client,
      instagram_account_id: "ig-123",
      user_access_token: "ig-user-token",
      image_relay: nil,
      sleeper: ->(seconds) { sleeps << seconds }
    )

    publisher.publish!(event_social_post: build_social_post(platform: "instagram"))

    assert_equal [ 2 ], sleeps
    assert_equal "https://graph.instagram.com/v25.0/container-1", client.calls.second.fetch(:url)
    assert_equal "https://graph.instagram.com/v25.0/container-1", client.calls.third.fetch(:url)
  end

  test "raises when container processing ends in an error state" do
    client = FakeMetaHttpClient.new(
      { "id" => "container-1" },
      { "id" => "container-1", "status_code" => "ERROR" }
    )
    publisher = Meta::InstagramPublisher.new(
      http_client: client,
      instagram_account_id: "ig-123",
      user_access_token: "ig-user-token",
      image_relay: nil
    )

    error = assert_raises(Meta::Error) do
      publisher.publish!(event_social_post: build_social_post(platform: "instagram"))
    end

    assert_equal "Instagram-Mediencontainer konnte nicht verarbeitet werden (Status: ERROR).", error.message
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

  class FakeImageRelay
    attr_reader :source_urls

    def initialize(relayed_url)
      @relayed_url = relayed_url
      @source_urls = []
    end

    def relay_image_url(source_url:)
      source_urls << source_url
      @relayed_url
    end
  end

  class FailingImageRelay
    def initialize(message)
      @message = message
    end

    def relay_image_url(source_url:)
      raise Meta::Error, @message
    end
  end
end
