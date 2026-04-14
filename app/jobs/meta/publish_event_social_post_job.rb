module Meta
  class PublishEventSocialPostJob < ApplicationJob
    discard_on ActiveJob::DeserializationError

    def perform(event_social_post_id, user_id)
      event_social_post = EventSocialPost.find(event_social_post_id)
      user = User.find(user_id)

      return if event_social_post.published?

      EventSocialPostPublisher.new.call(event_social_post:, user:)
    end
  end
end
