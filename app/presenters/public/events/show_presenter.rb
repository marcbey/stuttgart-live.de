module Public
  module Events
    class ShowPresenter
      Link = Data.define(:label, :url)
      Slide = Data.define(:source, :alt_text, :caption)

      WEEKDAY_LABELS = [ "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag" ].freeze

      attr_reader :event

      def initialize(event, primary_offer:, browse_state:, view_context:)
        @event = event
        @primary_offer = primary_offer
        @browse_state = browse_state
        @view_context = view_context
      end

      def page_title
        "#{meta_title} | Stuttgart Live"
      end

      def meta_title
        "#{event.artist_name} - #{event.title}"
      end

      def meta_description
        event.event_info.to_s.truncate(160)
      end

      def og_image_url
        image = event.image_for(slot: :social_card, breakpoint: :desktop)
        return view_context.optimized_event_image_url(image) if image.is_a?(EventImage)

        image&.image_url
      end

      def canonical_url
        view_context.event_url(event.slug)
      end

      def back_path
        view_context.root_path
      end

      def primary_source_label
        return if event.primary_source.blank?

        view_context.event_source_label(event.primary_source)
      end

      def header_classes
        classes = [ "event-detail-header" ]
        classes << "event-detail-header-with-image" if hero_image?
        classes.join(" ")
      end

      def hero_image?
        hero_desktop_image_source.present?
      end

      def hero_desktop_image_source
        @hero_desktop_image_source ||= view_context.event_image_source(hero_desktop_image)
      end

      def hero_mobile_image_source
        @hero_mobile_image_source ||= view_context.event_image_source(hero_mobile_image)
      end

      def hero_alt_text
        @hero_alt_text ||= event.artist_name.to_s.strip.presence || event.title.to_s
      end

      def hero_image_credit
        return editorial_hero_credit if editorial_hero_credit.present?
        return unless easyticket_import_hero_image?

        "Bildquelle: Easy Ticket Service / Veranstalter"
      end

      def primary_meta
        [ weekday_label, event_date_label, venue_location ].reject(&:blank?)
      end

      def schedule_line
        return if event.start_at.blank? || doors_at.blank?

        "Beginn: #{formatted_start_time} Uhr · Einlass: #{formatted_doors_time} Uhr"
      end

      def show_ticket_cta?
        primary_offer.present?
      end

      def ticket_badge_text
        event.badge_text.presence
      end

      def ticket_url
        primary_offer&.resolved_ticket_url
      end

      def ticket_price_text
        primary_offer&.ticket_price_text.to_s.presence
      end

      def visibility_badges
        @visibility_badges ||= view_context.public_event_visibility_badges(event)
      end

      def genres
        @genres ||= if event.association(:genres).loaded?
          event.genres.sort_by { |genre| [ genre.name.to_s, genre.id.to_i ] }.map(&:name)
        else
          event.genres.order(:name).pluck(:name)
        end
      end

      def social_links
        @social_links ||= [
          build_link("Homepage", event.homepage_url),
          build_link("Instagram", event.instagram_url),
          build_link("Facebook", event.facebook_url)
        ].compact
      end

      def youtube_embed_url
        event.youtube_embed_url.presence
      end

      def slider_items
        @slider_items ||= event.slider_images.to_a.filter_map do |image|
          source = view_context.event_image_source(image)
          next if source.blank?

          Slide.new(
            source: source,
            alt_text: view_context.event_image_alt(image, event),
            caption: image.sub_text.to_s
          )
        end
      end

      private

      attr_reader :primary_offer, :browse_state, :view_context

      def hero_desktop_image
        @hero_desktop_image ||= event.image_for(slot: :detail_hero, breakpoint: :desktop)
      end

      def hero_mobile_image
        @hero_mobile_image ||= event.image_for(slot: :grid_default, breakpoint: :mobile) || hero_desktop_image
      end

      def editorial_hero_credit
        return unless hero_desktop_image.is_a?(EventImage)

        credit = hero_desktop_image.sub_text.to_s.strip
        return if credit.blank?

        credit.start_with?("©") ? credit : "© #{credit}"
      end

      def easyticket_import_hero_image?
        hero_desktop_image.respond_to?(:source) &&
          !hero_desktop_image.is_a?(EventImage) &&
          hero_desktop_image.source.to_s.casecmp("easyticket").zero?
      end

      def doors_at
        @doors_at ||= event.doors_at || (event.start_at - 1.hour if event.start_at.present?)
      end

      def weekday_label
        return if event.start_at.blank?

        WEEKDAY_LABELS[event.start_at.wday]
      end

      def event_date_label
        return if event.start_at.blank?

        view_context.l(event.start_at.to_date, format: "%d.%m.%Y")
      end

      def formatted_start_time
        view_context.l(event.start_at, format: "%H:%M")
      end

      def formatted_doors_time
        view_context.l(doors_at, format: "%H:%M")
      end

      def venue_location
        [ event.venue, event.city ].reject(&:blank?).join(", ")
      end

      def build_link(label, url)
        normalized_url = url.to_s.strip.presence
        return if normalized_url.blank?

        Link.new(label: label, url: normalized_url)
      end
    end
  end
end
