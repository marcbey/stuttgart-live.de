module Meta
  class EventSocialPostPublisher
    def initialize(
      platform_publishers: default_platform_publishers,
      access_status: AccessStatus.new,
      connection_resolver: ConnectionResolver.new,
      draft_sync: EventSocialPostDraftSync.new
    )
      @platform_publishers = platform_publishers
      @access_status = access_status
      @connection_resolver = connection_resolver
      @draft_sync = draft_sync
    end

    def call(event_social_post:, user:)
      ensure_access_status!(event_social_post, user:)

      primary_result = publish_single!(event_social_post:, user:)
      publish_facebook_mirror!(instagram_post: event_social_post, user:) if publish_facebook_mirror?(event_social_post)
      primary_result
    end

    private

    attr_reader :access_status, :connection_resolver, :draft_sync, :platform_publishers

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
        when "facebook" then connection.selected_facebook_page_target
        else connection.selected_instagram_target
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

    def publish_single!(event_social_post:, user:)
      event_social_post.ensure_publishable!
      publish_context = publish_context_for(event_social_post.platform)
      publish_attempt = create_publish_attempt(event_social_post:, publish_context:, user:)

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

    def publish_facebook_mirror?(event_social_post)
      event_social_post.platform == EventSocialPost::CANONICAL_PLATFORM &&
        connection_resolver.connection&.selected_facebook_page_target.present?
    end

    def publish_facebook_mirror!(instagram_post:, user:)
      facebook_post = draft_sync.sync_facebook_mirror!(instagram_post)
      return if facebook_post.blank?

      publish_single!(event_social_post: facebook_post, user:)
    end

    def ensure_access_status!(event_social_post, user:)
      access_status.ensure_publishable!(force: true)
    rescue Error => error
      publish_context = publish_context_for(event_social_post.platform)
      publish_attempt = create_publish_attempt(event_social_post:, publish_context:, user:)
      event_social_post.mark_failed!(error.message) if event_social_post.persisted?
      publish_attempt&.fail!(message: error.message)
      raise
    end
  end
end
