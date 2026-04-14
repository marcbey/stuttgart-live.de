module Meta
  class EventSocialPostDraftBuilder
    attr_reader :event, :platform

    def initialize(event:, platform:)
      @event = event
      @platform = platform.to_s
    end

    def attributes
      {
        caption:,
        target_url:,
        image_url:,
        payload_snapshot: payload_snapshot
      }
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
      return if url_options[:host].blank?

      Rails.application.routes.url_helpers.event_url(event.slug, **url_options)
    end

    def image_url
      editorial_event_image_url || promotion_banner_image_url || social_card_image_url
    end

    def editorial_event_image_url
      media_url_for(event.event_image)
    end

    def social_card_image_url
      media_url_for(event.image_for(slot: :social_card, breakpoint: :desktop))
    end

    def promotion_banner_image_url
      return unless event.promotion_banner_image.attached?

      public_url_for(optimized_promotion_banner_representation)
    end

    def optimized_promotion_banner_representation
      event.processed_optimized_promotion_banner_image_variant
    rescue Event::ProcessingError, LoadError
      event.promotion_banner_image
    end

    def media_url_for(image)
      return if image.blank?
      return image.image_url.to_s.strip.presence unless image.is_a?(EventImage)
      return unless image.file.attached?

      public_url_for(optimized_event_representation(image))
    end

    def optimized_event_representation(image)
      image.processed_optimized_variant
    rescue EventImage::ProcessingError, LoadError
      image.file
    end

    def public_url_for(record)
      return if url_options[:host].blank?

      PublicMediaUrl.url_for(record, url_options:) ||
        Rails.application.routes.url_helpers.rails_storage_proxy_url(record, **url_options)
    end

    def url_options
      @url_options ||= begin
        options = Rails.application.config.action_mailer.default_url_options.to_h.symbolize_keys
        options[:host] ||= HetznerDeployConfig.app_host_if_present
        options[:protocol] ||= options[:host].to_s.include?("localhost") ? "http" : "https"
        options.compact
      end
    end

    def payload_snapshot
      {
        "platform" => platform,
        "caption" => caption,
        "target_url" => target_url,
        "image_url" => image_url,
        "generated_at" => Time.current.iso8601
      }
    end
  end
end
