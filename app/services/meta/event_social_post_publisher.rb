module Meta
  class EventSocialPostPublisher
    def initialize(platform_publishers: default_platform_publishers)
      @platform_publishers = platform_publishers
    end

    def call(event_social_post:, user:)
      event_social_post.ensure_publishable!
      event_social_post.mark_publishing!

      result = platform_publishers.fetch(event_social_post.platform) do
        raise Error, "Unbekannte Plattform: #{event_social_post.platform}"
      end.publish!(event_social_post:)

      event_social_post.mark_published!(
        user:,
        remote_media_id: result.remote_media_id,
        remote_post_id: result.remote_post_id,
        payload: { "publish_response" => result.payload }
      )

      result
    rescue Error => error
      event_social_post.mark_failed!(error.message) if event_social_post.persisted?
      raise
    end

    private

    attr_reader :platform_publishers

    def default_platform_publishers
      {
        "facebook" => FacebookPublisher.new,
        "instagram" => InstagramPublisher.new
      }
    end
  end
end
