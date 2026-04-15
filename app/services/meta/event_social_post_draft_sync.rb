require "stringio"

module Meta
  class EventSocialPostDraftSync
    def initialize(builder_class: EventSocialPostDraftBuilder, renderer: SocialCardRenderer.new)
      @builder_class = builder_class
      @renderer = renderer
    end

    def call(event:, platform:)
      social_post = event.event_social_posts.find_or_initialize_by(platform: platform.to_s)
      draft = builder_class.new(event:, platform:).build
      social_post.assign_draft_attributes!(draft.attributes)
      social_post.save!
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

      attach_or_purge!(social_post.preview_image, rendered_cards[:preview])
      attach_or_purge!(social_post.publish_image_facebook, rendered_cards[:facebook])
      attach_or_purge!(social_post.publish_image_instagram, rendered_cards[:instagram])

      social_post.update!(
        image_url: generated_image_url_for(social_post),
        payload_snapshot: social_post.payload_snapshot.deep_merge(
          "preview_image_url" => social_post.preview_image_url,
          "publish_image_facebook_url" => social_post.publish_image_facebook_url,
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
      rendered_cards.transform_values do |rendered_card|
        {
          "width" => rendered_card.width,
          "height" => rendered_card.height,
          "artist_lines" => rendered_card.artist_lines,
          "title_lines" => rendered_card.title_lines,
          "venue_text" => rendered_card.venue_text
        }
      end
    end

    def generated_image_url_for(social_post)
      case social_post.platform
      when "facebook"
        social_post.publish_image_facebook_url
      when "instagram"
        social_post.publish_image_instagram_url
      end
    end
  end
end
