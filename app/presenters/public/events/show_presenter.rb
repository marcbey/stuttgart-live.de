module Public
  module Events
    class ShowPresenter
      Link = Data.define(:label, :url)
      Slide = Data.define(:source, :alt_text, :caption)
      HeroGallerySlide = Data.define(:desktop_source, :mobile_source, :alt_text, :caption, :credit, :lightbox_source)
      FactItem = Data.define(:label, :value)
      PresenterItem = Data.define(:name, :external_url, :logo_source)
      VenueInfo = Data.define(:name, :address, :external_url, :logo_source)

      IMPORT_HERO_CREDIT_LABELS = {
        "easyticket" => "Easy Ticket Service",
        "eventim" => "Eventim",
        "reservix" => "Reservix"
      }.freeze
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
        [ schema_name, event_date_label, venue_location.presence || "Stuttgart" ].compact.join(" | ")
      end

      def meta_description
        summary = primary_description.presence || venue_description.presence
        return summary.to_s.truncate(160) if summary.present?

        [ schema_name, meta_schedule_label, venue_location.presence ].compact.join(" · ").truncate(160)
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
        source = event.primary_source.to_s.strip.presence || primary_offer&.source.to_s.strip.presence
        return if source.blank?

        view_context.event_source_label(source)
      end

      def header_classes
        classes = [ "event-detail-header" ]
        classes << "event-detail-header-with-image" if has_hero_gallery?
        classes.join(" ")
      end

      def hero_image?
        hero_desktop_image_source.present?
      end

      def has_hero_gallery?
        hero_gallery_slides.any?
      end

      def hero_desktop_image_source
        @hero_desktop_image_source ||= view_context.event_image_source(hero_desktop_image)
      end

      def hero_mobile_image_source
        @hero_mobile_image_source ||= view_context.event_image_source(hero_mobile_image)
      end

      def hero_alt_text
        @hero_alt_text ||= display_headline.to_s.strip.presence || schema_name
      end

      def display_headline
        event.artist_name.to_s.strip.presence || event.title.to_s.strip.presence || llm_enrichment&.event_description.to_s.strip.presence
      end

      def display_title
        event.title.to_s.strip.presence
      end

      def show_distinct_title?
        display_title.present? && !same_meaning?(display_headline, display_title)
      end

      def title_line
        display_title if show_distinct_title?
      end

      def hero_image_credit
        return editorial_hero_credit if editorial_hero_credit.present?
        source_label = import_hero_credit_label
        return if source_label.blank?

        "Bildquelle: #{source_label} / Veranstalter"
      end

      def hero_gallery_slides
        @hero_gallery_slides ||= begin
          slides = []

          if hero_image?
            slides << HeroGallerySlide.new(
              desktop_source: hero_desktop_image_source,
              mobile_source: hero_mobile_image_source,
              alt_text: hero_alt_text,
              caption: nil,
              credit: hero_image_credit,
              lightbox_source: hero_desktop_image_source
            )
          end

          slides.concat(
            slider_items.map do |item|
              HeroGallerySlide.new(
                desktop_source: item.source,
                mobile_source: nil,
                alt_text: item.alt_text,
                caption: item.caption.to_s.strip.presence,
                credit: nil,
                lightbox_source: item.source
              )
            end
          )

          slides
        end
      end

      def hero_gallery_rotates?
        hero_gallery_slides.size > 1
      end

      def hero_stage_aspect_ratio
        width, height = hero_stage_dimensions
        return unless width && height

        "#{width} / #{height}"
      end

      def hero_stage_max_width
        width, height = hero_stage_dimensions
        return unless width && height

        "#{(32.0 * width / height).round(4)}rem"
      end

      private

      def hero_stage_dimensions
        return unless hero_desktop_image.is_a?(EventImage)

        blob = hero_desktop_image.file.blob if hero_desktop_image.file.attached?
        metadata = blob&.metadata || {}
        width = metadata[:width] || metadata["width"]
        height = metadata[:height] || metadata["height"]
        return if width.to_i <= 0 || height.to_i <= 0

        [ width.to_i, height.to_i ]
      end

      public

      def fact_items
        @fact_items ||= [
          build_fact_item("Datum", meta_schedule_label),
          build_fact_item("Beginn", formatted_start_time.present? ? "#{formatted_start_time} Uhr" : nil),
          build_fact_item("Einlass", formatted_doors_time.present? ? "#{formatted_doors_time} Uhr" : nil),
          build_fact_item("Ort", venue_location)
        ].compact
      end

      def hero_meta_line
        [
          meta_schedule_label,
          venue_location
        ].compact.join(", ")
      end

      def hero_time_line
        [
          (formatted_start_time.present? ? "Beginn: #{formatted_start_time} Uhr" : nil),
          (formatted_doors_time.present? ? "Einlass #{formatted_doors_time} Uhr" : nil)
        ].compact.join(", ")
      end

      def schedule_line
        return if event.start_at.blank? || doors_at.blank?

        "Beginn: #{formatted_start_time} Uhr · Einlass: #{formatted_doors_time} Uhr"
      end

      def show_ticket_cta?
        primary_offer.present? && !event.past?
      end

      def ticket_badge_text
        event.badge_text.presence
      end

      def ticket_url
        return unless show_ticket_cta?

        primary_offer&.resolved_ticket_url
      end

      def ticket_price_text
        return unless show_ticket_cta?

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

      def enrichment_genres
        @enrichment_genres ||= Array(llm_enrichment&.genre).filter_map do |entry|
          entry.to_s.strip.presence
        end
      end

      def genre_tags
        @genre_tags ||= (genres + enrichment_genres).uniq
      end

      def detail_genres
        genre_tags
      end

      def external_links
        @external_links ||= [
          build_link("Homepage", event.homepage_url, llm_enrichment&.homepage_link),
          build_link("Instagram", event.instagram_url, llm_enrichment&.instagram_link),
          build_link("Facebook", event.facebook_url, llm_enrichment&.facebook_link),
          youtube_fallback_link
        ].compact
      end

      def social_links
        external_links
      end

      def youtube_embed_url
        embed_url_for(primary_youtube_url)
      end

      def primary_description
        @primary_description ||= normalized_copy(
          event.event_info.to_s.strip.presence || llm_enrichment&.event_description.to_s.strip.presence
        )
      end

      def description_text
        primary_description
      end

      def artist_description
        nil
      end

      def venue_description
        @venue_description ||= normalized_copy(event.venue_description)
      end

      def support_text
        event.support.to_s.strip.presence
      end

      def has_media_block?
        youtube_embed_url.present?
      end

      def presenters
        @presenters ||= event.ordered_presenters.filter_map do |presenter|
          logo_source = view_context.presenter_logo_source(presenter, size: :detail)
          next if logo_source.blank?

          PresenterItem.new(
            name: presenter.name,
            external_url: presenter.external_url,
            logo_source:
          )
        end
      end

      def has_presenters?
        presenters.any?
      end

      def venue_info
        return @venue_info if defined?(@venue_info)

        venue = event.venue_record
        return @venue_info = nil if venue.blank?

        @venue_info = VenueInfo.new(
          name: venue.name,
          address: venue.address.to_s.strip.presence,
          external_url: venue.external_url.to_s.strip.presence,
          logo_source: view_context.venue_logo_source(venue, size: :detail)
        )
      end

      def has_secondary_content?
        has_media_block? || venue_description.present? || support_text.present?
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

      def schema_name
        [ display_headline, title_line ].compact.join(" – ").presence || display_headline
      end

      def schema_json_ld
        data = {
          "@context" => "https://schema.org",
          "@type" => schema_type,
          name: schema_name,
          description: meta_description,
          startDate: event.start_at&.iso8601,
          url: canonical_url,
          eventAttendanceMode: "https://schema.org/OfflineEventAttendanceMode",
          eventStatus: "https://schema.org/EventScheduled",
          image: og_image_url.presence && [ og_image_url ],
          location: schema_location,
          organizer: schema_organizer,
          offers: schema_offer
        }.compact

        if doors_at.present?
          data[:doorTime] = doors_at.iso8601
        end

        data.to_json
      end

      private

      attr_reader :primary_offer, :browse_state, :view_context

      def llm_enrichment
        @llm_enrichment ||= event.llm_enrichment
      end

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

      def import_hero_credit_label
        return unless hero_desktop_image.respond_to?(:source)
        return if hero_desktop_image.is_a?(EventImage)

        IMPORT_HERO_CREDIT_LABELS[hero_desktop_image.source.to_s.downcase]
      end

      def doors_at
        @doors_at ||= event.doors_at
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
        return if event.start_at.blank?

        view_context.l(event.start_at, format: "%H:%M")
      end

      def formatted_doors_time
        return if doors_at.blank?

        view_context.l(doors_at, format: "%H:%M")
      end

      def venue_location
        venue = event.venue.to_s.strip.presence
        city = event.city.to_s.strip.presence
        return city if venue.blank?
        return venue if city.blank?
        return venue if venue_contains_city?(venue, city)

        [ venue, city ].join(", ")
      end

      def meta_schedule_label
        [ weekday_label, event_date_label ].compact.join(", ")
      end

      def meta_location_context
        [ event_date_label, venue_location.presence || "Stuttgart" ].compact.join(" · ")
      end

      def venue_contains_city?(venue, city)
        normalized_venue = normalize_comparison_token(venue)
        normalized_city = normalize_comparison_token(city)
        normalized_venue.include?(normalized_city)
      end

      def primary_youtube_url
        event.youtube_url.to_s.strip.presence || llm_enrichment&.youtube_link.to_s.strip.presence
      end

      def youtube_fallback_link
        return if primary_youtube_url.blank?
        return if youtube_embed_url.present?

        build_link("YouTube", primary_youtube_url)
      end

      def embed_url_for(url)
        normalized_url = url.to_s.strip.presence
        return if normalized_url.blank?

        id = event.send(:extract_youtube_id, normalized_url)
        return if id.blank?

        "https://www.youtube.com/embed/#{id}"
      end

      def build_link(label, *urls)
        normalized_url = urls.filter_map { |url| url.to_s.strip.presence }.first
        return if normalized_url.blank?

        Link.new(label: label, url: normalized_url)
      end

      def build_fact_item(label, value)
        normalized_value = value.to_s.strip.presence
        return if normalized_value.blank?

        FactItem.new(label: label, value: normalized_value)
      end

      def normalized_copy(text)
        normalized_text = text.to_s.strip
        return if normalized_text.blank?

        paragraphs = normalized_text.split(/\n{2,}/).map { |paragraph| paragraph.strip }.reject(&:blank?)
        unique_paragraphs = paragraphs.uniq { |paragraph| normalize_comparison_token(paragraph) }
        unique_paragraphs.join("\n\n")
      end

      def same_meaning?(left, right)
        normalize_comparison_token(left) == normalize_comparison_token(right)
      end

      def normalize_comparison_token(value)
        value.to_s.downcase.gsub(/[^[:alnum:]]+/, "")
      end

      def schema_type
        "Event"
      end

      def schema_location
        return if event.venue.blank? && event.city.blank? && event.venue_address.blank?

        {
          "@type" => "Place",
          name: event.venue.to_s.strip.presence,
          address: event.venue_address.to_s.strip.presence || event.city.to_s.strip.presence
        }.compact
      end

      def schema_organizer
        return unless event.show_public_organizer_notes?

        {
          "@type" => "Organization",
          name: "Russ Live"
        }
      end

      def schema_offer
        return if ticket_url.blank?

        offer = {
          "@type" => "Offer",
          url: ticket_url,
          availability: "https://schema.org/InStock",
          priceCurrency: "EUR"
        }

        if event.min_price.present?
          offer[:lowPrice] = event.min_price.to_s
          offer[:price] = event.min_price.to_s if event.max_price.blank? || event.min_price == event.max_price
        end

        offer[:highPrice] = event.max_price.to_s if event.max_price.present?
        offer
      end
    end
  end
end
