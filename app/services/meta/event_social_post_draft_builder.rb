module Meta
  class EventSocialPostDraftBuilder
    Draft = Data.define(:attributes, :card_payload, :background_source)
    BackgroundSource = Data.define(:source_type, :attachment, :remote_url, :focus_x, :focus_y, :zoom, :source_label)

    attr_reader :event, :platform

    def initialize(event:, platform:)
      @event = event
      @platform = platform.to_s
    end

    def build
      Draft.new(
        attributes: {
          caption:,
          target_url:,
          image_url: nil,
          payload_snapshot: payload_snapshot
        },
        card_payload:,
        background_source:
      )
    end

    def attributes
      build.attributes
    end

    private

    def caption
      lines = [ headline, schedule_line, venue_line ].compact
      lines << "Mehr Infos und Tickets:"
      lines << target_url if target_url.present?
      lines.join("\n")
    end

    def headline
      [ event.artist_name.to_s.strip.presence, event.title.to_s.strip.presence ].compact.uniq.join(" | ").presence
    end

    def schedule_line
      return unless event.start_at.present?

      "#{I18n.l(event.start_at.to_date, format: "%d.%m.%Y")} · Beginn #{event.start_at.in_time_zone.strftime("%H:%M")} Uhr"
    end

    def venue_line
      [ event.venue.to_s.strip.presence, event.city.to_s.strip.presence ].compact.join(", ").presence
    end

    def target_url
      return if Meta::PublicAssetUrl.url_options[:host].blank?

      Rails.application.routes.url_helpers.event_url(event.slug, **Meta::PublicAssetUrl.url_options)
    end

    def card_payload
      {
        artist_name: event.artist_name.to_s.strip,
        meta_line: default_card_meta_line
      }
    end

    def background_source
      editorial_background_source || promotion_banner_background_source || social_card_background_source
    end

    def editorial_background_source
      image = event.event_image
      return unless image.is_a?(EventImage) && image.file.attached?

      BackgroundSource.new(
        source_type: :attachment,
        attachment: image.file,
        remote_url: nil,
        focus_x: image.card_focus_x_value,
        focus_y: image.card_focus_y_value,
        zoom: image.card_zoom_value,
        source_label: "editorial_event_image"
      )
    end

    def promotion_banner_background_source
      return unless event.promotion_banner_image.attached?

      BackgroundSource.new(
        source_type: :attachment,
        attachment: event.promotion_banner_image,
        remote_url: nil,
        focus_x: event.promotion_banner_image_focus_x_value,
        focus_y: event.promotion_banner_image_focus_y_value,
        zoom: event.promotion_banner_image_zoom_value,
        source_label: "promotion_banner_image"
      )
    end

    def social_card_background_source
      image = event.image_for(slot: :social_card, breakpoint: :desktop)
      return if image.blank?

      if image.is_a?(EventImage) && image.file.attached?
        return BackgroundSource.new(
          source_type: :attachment,
          attachment: image.file,
          remote_url: nil,
          focus_x: image.card_focus_x_value,
          focus_y: image.card_focus_y_value,
          zoom: image.card_zoom_value,
          source_label: "event_image_fallback"
        )
      end

      remote_url = image.image_url.to_s.strip.presence
      return if remote_url.blank?

      BackgroundSource.new(
        source_type: :remote_url,
        attachment: nil,
        remote_url:,
        focus_x: EventImage::DEFAULT_CARD_FOCUS_X,
        focus_y: EventImage::DEFAULT_CARD_FOCUS_Y,
        zoom: EventImage::DEFAULT_CARD_ZOOM,
        source_label: "import_image"
      )
    end

    def payload_snapshot
      {
        "platform" => platform,
        "caption" => caption,
        "target_url" => target_url,
        "image_url" => nil,
        "card_text" => card_payload.deep_stringify_keys,
        "background_source" => background_source&.source_label,
        "generated_at" => Time.current.iso8601
      }
    end

    def default_card_meta_line
      [
        event.start_at.present? ? I18n.l(event.start_at.to_date, format: "%d.%m.%Y") : nil,
        event.venue.to_s.strip.presence
      ].compact.join(" · ").presence.to_s
    end
  end
end
