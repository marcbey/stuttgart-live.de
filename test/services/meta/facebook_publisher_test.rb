require "test_helper"

class Meta::FacebookPublisherTest < ActiveSupport::TestCase
  test "publishes a photo post and returns remote ids" do
    client = FakeMetaHttpClient.new(
      { "id" => "photo-1", "post_id" => "page-post-1" }
    )
    publisher = Meta::FacebookPublisher.new(
      http_client: client,
      page_id: "12345",
      page_access_token: "page-token"
    )

    result = publisher.publish!(event_social_post: build_social_post(platform: "facebook"))

    assert_equal "https://graph.facebook.com/v25.0/12345/photos", client.calls.first.fetch(:url)
    assert_equal "page-token", client.calls.first.fetch(:params).fetch(:access_token)
    assert_equal "photo-1", result.remote_media_id
    assert_equal "page-post-1", result.remote_post_id
  end

  test "stores the derived facebook post url when the post id contains page and post ids" do
    client = FakeMetaHttpClient.new(
      { "id" => "photo-1", "post_id" => "1065331226666212_122101097324744282" }
    )
    publisher = Meta::FacebookPublisher.new(
      http_client: client,
      page_id: "12345",
      page_access_token: "page-token"
    )

    result = publisher.publish!(event_social_post: build_social_post(platform: "facebook"))

    assert_equal "https://www.facebook.com/1065331226666212/posts/122101097324744282", result.payload.fetch("post_url")
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
  end
end
