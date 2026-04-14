module Meta
  class EventSocialPostDraftSync
    def initialize(builder_class: EventSocialPostDraftBuilder)
      @builder_class = builder_class
    end

    def call(event:, platform:)
      social_post = event.event_social_posts.find_or_initialize_by(platform: platform.to_s)
      social_post.assign_draft_attributes!(builder_class.new(event:, platform:).attributes)
      social_post.save!
      social_post
    end

    private

    attr_reader :builder_class
  end
end
