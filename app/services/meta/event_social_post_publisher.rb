module Meta
  class EventSocialPostPublisher
    def initialize(
      platform_publishers: default_platform_publishers,
      access_status: AccessStatus.new,
      connection_resolver: ConnectionResolver.new
    )
      @platform_publishers = platform_publishers
      @access_status = access_status
      @connection_resolver = connection_resolver
    end

    def call(event_social_post:, user:)
      event_social_post.ensure_publishable!
      publish_context = publish_context_for(event_social_post.platform)
      publish_attempt = create_publish_attempt(event_social_post:, publish_context:, user:)
      access_status.ensure_publishable!(force: true)

      result = platform_publishers.fetch(event_social_post.platform) do
        raise Error, "Unbekannte Plattform: #{event_social_post.platform}"
      end.publish!(event_social_post:)

      event_social_post.mark_published!(
        user:,
        remote_media_id: result.remote_media_id,
        remote_post_id: result.remote_post_id,
        payload: { "publish_response" => result.payload }
      )
      publish_attempt&.succeed!(response_snapshot: { "publish_response" => result.payload })

      result
    rescue Error => error
      event_social_post.mark_failed!(error.message) if event_social_post.persisted?
      publish_attempt&.fail!(message: error.message)
      raise
    end

    private

    attr_reader :access_status, :connection_resolver, :platform_publishers

    def default_platform_publishers
      {
        "facebook" => FacebookPublisher.new,
        "instagram" => InstagramPublisher.new
      }
    end

    def publish_context_for(platform)
      connection = connection_resolver.connection
      return { connection: nil, target: nil } if connection.blank?

      target =
        case platform.to_s
        when "facebook"
          connection.selected_facebook_page_target
        when "instagram"
          connection.selected_instagram_target
        end

      { connection:, target: }
    end

    def create_publish_attempt(event_social_post:, publish_context:, user:)
      event_social_post.publish_attempts.create!(
        social_connection: publish_context.fetch(:connection),
        social_connection_target: publish_context.fetch(:target),
        initiated_by: user,
        platform: event_social_post.platform,
        status: "started",
        started_at: Time.current,
        request_snapshot: {
          "connection_status" => publish_context.fetch(:connection)&.connection_status,
          "target_id" => publish_context.fetch(:target)&.id,
          "target_external_id" => publish_context.fetch(:target)&.external_id
        }.compact
      )
    end
  end
end
