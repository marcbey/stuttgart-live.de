module Meta
  class PublishEventSocialPostJob < ApplicationJob
    discard_on ActiveJob::DeserializationError

    def perform(event_social_post_id, user_id)
      event_social_post = EventSocialPost.find(event_social_post_id)
      return if event_social_post.published?

      user = User.find_by(id: user_id)
      unless user
        event_social_post.mark_failed!("Veröffentlichung abgebrochen: Der auslösende Benutzer wurde gelöscht.")
        return
      end

      EventSocialPostPublisher.new.call(event_social_post:, user:)
    end
  end
end
