require "stringio"

module Meta
  class EventSocialPostDraftSync
    def initialize(builder_class: EventSocialPostDraftBuilder, renderer: SocialCardRenderer.new)
      @builder_class = builder_class
      @renderer = renderer
    end

    def call(event:, platform:)
      normalized_platform = EventSocialPost::CANONICAL_PLATFORM
      social_post = event.event_social_posts.find_or_initialize_by(platform: normalized_platform)
      draft = builder_class.new(event:, platform: normalized_platform).build
      social_post.assign_draft_attributes!(draft.attributes)
      social_post.save!
      sync_rendered_assets!(social_post, draft:)
      social_post
    end

    def refresh_rendered_assets!(social_post)
      base_draft = builder_class.new(event: social_post.event, platform: social_post.platform).build
      draft = builder_class::Draft.new(
        attributes: base_draft.attributes,
        card_payload: social_post.card_payload,
        background_source: base_draft.background_source
      )

      sync_rendered_assets!(social_post, draft:)
      social_post
    end

    private

    attr_reader :builder_class, :renderer

    def sync_rendered_assets!(social_post, draft:)
      rendered_cards = renderer.render_set(
        background_source: draft.background_source,
        card_payload: draft.card_payload,
        slug: social_post.event.slug
      )

      attach_or_purge!(social_post.publish_image_instagram, rendered_cards[:instagram])

      social_post.update!(
        image_url: generated_image_url_for(social_post),
        payload_snapshot: social_post.payload_snapshot.deep_merge(
          "publish_image_instagram_url" => social_post.publish_image_instagram_url,
          "rendered_variants" => rendered_variant_payload(rendered_cards)
        )
      )
    end

    def attach_or_purge!(attachment, rendered_card)
      if rendered_card.present?
        attachment.attach(
          io: StringIO.new(rendered_card.binary),
          filename: rendered_card.filename,
          content_type: rendered_card.content_type
        )
      elsif attachment.attached?
        attachment.purge
      end
    end

    def rendered_variant_payload(rendered_cards)
      rendered_cards.deep_stringify_keys.transform_values do |rendered_card|
        {
          "width" => rendered_card.width,
          "height" => rendered_card.height,
          "artist_lines" => rendered_card.artist_lines,
          "meta_line" => rendered_card.meta_line
        }
      end
    end

    def generated_image_url_for(social_post)
      social_post.publish_image_instagram_url
    end
  end
end
