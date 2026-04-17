module ApplicationHelper
  GOOGLE_ANALYTICS_ALLOWED_HOSTS = %w[
    stuttgart-live.de
    www.stuttgart-live.de
  ].freeze
  LOCAL_FONT_FACES = {
    shared: [
      { family: "Archivo Narrow", weight: 400, logical_path: "archivo-narrow-400.woff2" },
      { family: "Archivo Narrow", weight: 700, logical_path: "archivo-narrow-700.woff2" },
      { family: "Oswald", weight: 500, logical_path: "oswald-500.woff2" },
      { family: "Oswald", weight: 700, logical_path: "oswald-700.woff2" }
    ],
    frontend: [
      { family: "Bebas Neue", weight: 400, logical_path: "bebas-neue-400.woff2" }
    ]
  }.freeze

  def app_nav_link_class(active: false, accent: false)
    classes = [ "app-nav-link" ]
    classes << "app-nav-link-active" if active
    classes << "app-nav-link-accent" if accent
    classes.join(" ")
  end

  def local_font_face_stylesheet(frontend:)
    font_faces = LOCAL_FONT_FACES[:shared]
    font_faces += LOCAL_FONT_FACES[:frontend] if frontend
    available_font_faces = font_faces.select { |font_face| asset_available?(font_face[:logical_path]) }

    safe_join(available_font_faces.map { |font_face| local_font_face_rule(**font_face) }, "\n".html_safe)
  end

  def events_nav_active?
    controller_path == "public/events"
  end

  def news_nav_active?
    controller_path == "public/news"
  end

  def contact_nav_active?
    controller_path == "public/pages" && public_page_slug == "kontakt"
  end

  def imprint_nav_active?
    controller_path == "public/pages" && public_page_slug == "impressum"
  end

  def backend_nav_active?
    controller_path == "backend/events"
  end

  def blog_nav_active?
    controller_path == "backend/blog_posts"
  end

  def pages_nav_active?
    controller_path == "backend/pages"
  end

  def presenter_nav_active?
    controller_path == "backend/presenters"
  end

  def venue_nav_active?
    controller_path == "backend/venues"
  end

  def importer_nav_active?
    controller_path == "backend/import_sources" || controller_path == "backend/import_runs"
  end

  def settings_nav_active?
    controller_path == "backend/settings"
  end

  def compiled_asset_exists?(logical_path)
    asset_available?(logical_path)
  end

  def asset_available?(logical_path)
    manifest_assets =
      if Rails.application.respond_to?(:assets_manifest)
        Rails.application.assets_manifest&.assets
      end
    return true if manifest_assets&.key?(logical_path)

    if Rails.application.respond_to?(:assets)
      propshaft_asset = Rails.application.assets.load_path.find(logical_path)
      return true if propshaft_asset.present?
    end

    builds_path = Rails.root.join("app/assets/builds", logical_path)
    return true if File.exist?(builds_path)

    propshaft_path = Rails.root.join("app/assets", logical_path)
    File.exist?(propshaft_path)
  rescue StandardError
    false
  end

  def google_analytics_measurement_id
    return unless google_analytics_allowed_host?

    Rails.configuration.x.google_analytics_measurement_id.to_s.strip.presence
  end

  def local_font_face_rule(family:, weight:, logical_path:)
    <<~CSS.html_safe
      @font-face {
        font-family: "#{ERB::Util.html_escape(family)}";
        font-style: normal;
        font-weight: #{weight};
        font-display: swap;
        src: url("#{ERB::Util.html_escape(asset_path(logical_path))}") format("woff2");
      }
    CSS
  end

  def google_analytics_enabled?
    google_analytics_measurement_id.present?
  end

  def google_analytics_allowed_host?
    GOOGLE_ANALYTICS_ALLOWED_HOSTS.include?(request.host)
  end

  def event_card_image_style(image)
    return nil unless image.is_a?(EventImage)

    [
      "object-position: #{image.card_focus_x_value}% #{image.card_focus_y_value}%",
      "--event-card-base-scale: #{(image.card_zoom_value / 100.0).round(3)}",
      "transform-origin: #{image.card_focus_x_value}% #{image.card_focus_y_value}%"
    ].join("; ")
  end

  def optimized_event_image_representation(image)
    return if image.blank?
    return image unless image.is_a?(EventImage)

    image.processed_optimized_variant
  rescue EventImage::ProcessingError, LoadError
    image.file
  end

  def optimized_event_image_source(image, strict_proxy: false)
    return if image.blank?
    return image.image_url unless image.is_a?(EventImage)

    representation = optimized_event_image_representation(image)
    return if representation.blank?

    return strict_public_media_path(representation, image.file) if strict_proxy

    public_media_path(representation)
  end

  def optimized_event_image_url(image)
    return if image.blank?
    return image.image_url unless image.is_a?(EventImage)

    public_media_url(optimized_event_image_representation(image))
  end

  def event_cropped_image_style(image, frame_ratio:)
    return event_card_image_style(image) unless image.is_a?(EventImage)

    cropped_attachment_style(
      attachment: image.file,
      focus_x: image.card_focus_x_value,
      focus_y: image.card_focus_y_value,
      zoom: image.card_zoom_value,
      frame_ratio: frame_ratio,
      fallback_style: focused_cropped_fallback_style(
        focus_x: image.card_focus_x_value,
        focus_y: image.card_focus_y_value,
        zoom: image.card_zoom_value
      )
    )
  end

  def optimized_event_promotion_banner_image_representation(event)
    return unless event.promotion_banner_image.attached?

    event.processed_optimized_promotion_banner_image_variant
  rescue Event::ProcessingError, LoadError
    event.promotion_banner_image
  end

  def optimized_event_promotion_banner_image_source(event, strict_proxy: false)
    representation = optimized_event_promotion_banner_image_representation(event)
    return if representation.blank?

    return strict_public_media_path(representation, event.promotion_banner_image) if strict_proxy

    public_media_path(representation)
  end

  def event_promotion_banner_image_style(event, frame_ratio:)
    cropped_attachment_style(
      attachment: event.promotion_banner_image,
      focus_x: event.promotion_banner_image_focus_x_value,
      focus_y: event.promotion_banner_image_focus_y_value,
      zoom: event.promotion_banner_image_zoom_value,
      frame_ratio: frame_ratio,
      fallback_style: focused_cropped_fallback_style(
        focus_x: event.promotion_banner_image_focus_x_value,
        focus_y: event.promotion_banner_image_focus_y_value,
        zoom: event.promotion_banner_image_zoom_value
      )
    )
  end

  def presenter_logo_representation(presenter, size: :detail)
    return if presenter.blank? || !presenter.logo.attached?

    case size.to_sym
    when :thumbnail
      presenter.thumbnail_logo_variant
    else
      presenter.detail_logo_variant
    end
  end

  def presenter_logo_source(presenter, size: :detail)
    representation = presenter_logo_representation(presenter, size:)
    return if representation.blank?

    public_media_path(representation)
  end

  def venue_logo_representation(venue, size: :detail)
    return if venue.blank? || !venue.logo.attached?

    case size.to_sym
    when :thumbnail
      venue.thumbnail_logo_variant
    else
      venue.detail_logo_variant
    end
  end

  def venue_logo_source(venue, size: :detail)
    representation = venue_logo_representation(venue, size:)
    return if representation.blank?

    public_media_path(representation)
  end

  def blog_post_image_style(blog_post, slot)
    focused_image_style(
      focus_x: blog_post.public_send("#{slot}_focus_x_value"),
      focus_y: blog_post.public_send("#{slot}_focus_y_value"),
      zoom: blog_post.public_send("#{slot}_zoom_value")
    )
  end

  def optimized_blog_post_image_representation(blog_post, slot)
    return unless blog_post.present?

    attachment = blog_post.public_send(slot)
    return attachment unless attachment.attached?

    blog_post.processed_optimized_image_variant(slot)
  rescue BlogPost::ProcessingError, LoadError
    attachment
  end

  def optimized_blog_post_image_url(blog_post, slot)
    representation = optimized_blog_post_image_representation(blog_post, slot)
    return if representation.blank?

    public_media_url(representation)
  end

  def optimized_blog_post_image_source(blog_post, slot, strict_proxy: false)
    representation = optimized_blog_post_image_representation(blog_post, slot)
    return if representation.blank?

    return strict_public_media_path(representation, blog_post.public_send(slot)) if strict_proxy

    public_media_path(representation)
  end

  def formatted_venue_address(address)
    lines = address.to_s.split(",").map(&:strip).reject(&:blank?)
    return if lines.blank?

    if lines.length > 1 && lines.last.casecmp?("deutschland")
      country = lines.pop
      lines[-1] = "#{lines.last}, #{country}"
    end

    safe_join(
      lines.each_with_index.map do |line, index|
        formatted_line = index == lines.length - 1 ? line : "#{line},"
        tag.span(formatted_line, class: "event-detail-venue-address-line")
      end
    )
  end

  def public_media_path(record, strict_proxy: false)
    return if record.blank?

    proxied_path = PublicMediaUrl.path_for(record)
    return proxied_path if proxied_path.present?
    return if strict_proxy

    rails_storage_proxy_path(record, only_path: true)
  end

  def public_media_url(record, strict_proxy: false)
    return if record.blank?

    proxied_url = PublicMediaUrl.url_for(record, url_options: media_url_options)
    return proxied_url if proxied_url.present?
    return if strict_proxy

    rails_storage_proxy_url(record)
  end

  def public_rich_text_representation_source(blob, in_gallery: false)
    representation = blob.representation(resize_to_limit: in_gallery ? [ 800, 600 ] : [ 1024, 768 ]).processed
    public_media_path(representation)
  rescue LoadError, MiniMagick::Error, ActiveStorage::InvariableError, ImageProcessing::Error
    public_media_path(blob)
  end

  def blog_post_cropped_image_style(blog_post, slot, frame_ratio:, lock_top: false)
    cropped_attachment_style(
      attachment: blog_post.public_send(slot),
      focus_x: blog_post.public_send("#{slot}_focus_x_value"),
      focus_y: blog_post.public_send("#{slot}_focus_y_value"),
      zoom: blog_post.public_send("#{slot}_zoom_value"),
      frame_ratio: frame_ratio,
      lock_top: lock_top,
      fallback_style: focused_cropped_fallback_style(
        focus_x: blog_post.public_send("#{slot}_focus_x_value"),
        focus_y: blog_post.public_send("#{slot}_focus_y_value"),
        zoom: blog_post.public_send("#{slot}_zoom_value"),
        lock_top: lock_top
      )
    )
  end

  def blog_post_image_copyright(blog_post, slot)
    blog_post.public_send("#{slot}_copyright")
  end

  def homepage_media_strict_proxy?
    Rails.env.production? || PublicMediaUrl.enabled?
  end

  def formatted_organizer_notes(notes)
    formatted_organizer_notes_with_link(notes)
  end

  private

  def strict_public_media_path(*records)
    records.compact.each do |record|
      path = public_media_path(record, strict_proxy: true)
      return path if path.present?
    end

    nil
  end

  def focused_image_style(focus_x:, focus_y:, zoom:)
    [
      "object-position: #{focus_x}% #{focus_y}%",
      "transform: scale(#{(zoom.to_f / 100.0).round(3)})",
      "transform-origin: #{focus_x}% #{focus_y}%"
    ].join("; ")
  end

  def focused_cropped_fallback_style(focus_x:, focus_y:, zoom:, lock_top: false)
    zoom_scale = zoom.to_f / 100.0
    offset_x = 0.5 - ((focus_x.to_f / 100.0) * zoom_scale)
    offset_y = 0.5 - ((focus_y.to_f / 100.0) * zoom_scale)
    offset_y = 0 if lock_top

    [
      "position: absolute",
      "left: #{(offset_x * 100).round(3)}%",
      "top: #{(offset_y * 100).round(3)}%",
      "width: #{(zoom_scale * 100).round(3)}%",
      "height: #{(zoom_scale * 100).round(3)}%",
      "object-fit: cover",
      "max-width: none",
      "max-height: none"
    ].join("; ")
  end

  def cropped_attachment_style(attachment:, focus_x:, focus_y:, zoom:, frame_ratio:, fallback_style:, lock_top: false)
    metadata = analyzed_attachment_metadata(attachment)
    image_width = metadata_value(metadata, :width).to_f
    image_height = metadata_value(metadata, :height).to_f

    return fallback_style unless image_width.positive? && image_height.positive?

    focus_x = focus_x.to_f / 100.0
    focus_y = focus_y.to_f / 100.0
    zoom_scale = zoom.to_f / 100.0
    image_ratio = image_width / image_height

    width_factor, height_factor =
      if image_ratio > frame_ratio
        [ (image_ratio / frame_ratio) * zoom_scale, zoom_scale ]
      else
        [ zoom_scale, (frame_ratio / image_ratio) * zoom_scale ]
      end

    offset_x = clamp_crop_offset(0.5 - (focus_x * width_factor), width_factor)
    offset_y = clamp_crop_offset(0.5 - (focus_y * height_factor), height_factor)
    offset_y = 0 if lock_top

    [
      "position: absolute",
      "left: #{(offset_x * 100).round(3)}%",
      "top: #{(offset_y * 100).round(3)}%",
      "width: #{(width_factor * 100).round(3)}%",
      "height: #{(height_factor * 100).round(3)}%",
      "object-fit: cover",
      "max-width: none",
      "max-height: none"
    ].join("; ")
  end

  def analyzed_attachment_metadata(attachment)
    return {} unless attachment.respond_to?(:attached?) && attachment.attached?

    blob = attachment.blob
    metadata = blob.metadata || {}
    return metadata if metadata_dimensions_present?(metadata)
    return metadata if blob.analyzed?

    blob.analyze
    blob.reload.metadata || metadata
  rescue StandardError
    metadata || {}
  end

  def metadata_dimensions_present?(metadata)
    metadata_value(metadata, :width).to_i.positive? && metadata_value(metadata, :height).to_i.positive?
  end

  def metadata_value(metadata, key)
    metadata[key.to_s] || metadata[key.to_sym]
  end

  def clamp_crop_offset(offset, size_factor)
    [ [ offset, 0 ].min, 1 - size_factor ].max
  end

  def formatted_organizer_notes_with_link(notes, event: nil)
    lines = notes.to_s.lines.map(&:rstrip)
    blocks = []
    paragraph_lines = []
    current_list = nil

    flush_paragraph = lambda do
      next if paragraph_lines.empty?

      blocks << content_tag(:p, safe_join(paragraph_lines.map { |line| organizer_notes_inline_content(line, event:) }, tag.br))
      paragraph_lines = []
    end

    flush_list = lambda do
      next unless current_list

      items = current_list.fetch(:items).map do |item|
        content_tag(:li, class: "event-detail-notes-list-item #{current_list[:item_class]}".strip) do
          marker = content_tag(:span, item.fetch(:marker), class: "event-detail-notes-list-marker", aria: { hidden: true })
          text = content_tag(:span, organizer_notes_inline_content(item.fetch(:text), event:), class: "event-detail-notes-list-text")
          safe_join([ marker, text ])
        end
      end

      blocks << content_tag(:ul, safe_join(items), class: "event-detail-notes-list #{current_list[:list_class]}".strip)
      current_list = nil
    end

    lines.each_with_index do |raw_line, index|
      line = raw_line.strip

      if line.blank?
        flush_paragraph.call
        flush_list.call
        next
      end

      list_item = organizer_notes_list_item(line)

      if list_item
        flush_paragraph.call

        if current_list && current_list[:list_class] != list_item[:list_class]
          flush_list.call
        end

        current_list ||= {
          list_class: list_item.fetch(:list_class),
          item_class: list_item.fetch(:item_class),
          items: []
        }
        current_list[:items] << list_item
        next
      end

      flush_list.call

      if organizer_notes_heading?(line, lines[(index + 1)..])
        flush_paragraph.call
        blocks << content_tag(:h3, line.delete_suffix(":"), class: "event-detail-notes-heading")
      else
        paragraph_lines << line
      end
    end

    flush_paragraph.call
    flush_list.call

    safe_join(blocks)
  end

  private

  def organizer_notes_inline_content(text, event:)
    escaped = ERB::Util.html_escape(text.to_s)
    escaped
      .gsub("(Das Begleitformular findest Du HIER)", organizer_notes_begleitformular_link(event:))
      .gsub("→ Begleitformular PDF", organizer_notes_begleitformular_link(event:))
      .html_safe
  end

  def organizer_notes_begleitformular_link(event:)
    link_to(
      "<span class=\"inline-arrow\">→</span> Begleitformular <span class=\"inline-file-badge\">PDF</span>".html_safe,
      begleitformular_path(
        event: [ event&.artist_name, event&.title ].compact.join(" - ").presence,
        venue: event&.venue,
        date: event&.start_at&.to_date&.iso8601
      )
    )
  end

  def organizer_notes_heading?(line, following_lines)
    return true if line.end_with?(":") && !line.include?(",")
    return false if line.match?(/[.,:;!?]\z/)

    following_lines.to_a.lazy.map(&:strip).reject(&:blank?).first.then do |next_line|
      next_line.present? && organizer_notes_list_item(next_line).present?
    end
  end

  def organizer_notes_list_item(line)
    case line
    when /\A✅\s+(.+)\z/
      { marker: "✅", text: Regexp.last_match(1), list_class: "event-detail-notes-list-positive", item_class: "event-detail-notes-list-item-positive" }
    when /\A❌\s+(.+)\z/
      { marker: "❌", text: Regexp.last_match(1), list_class: "event-detail-notes-list-negative", item_class: "event-detail-notes-list-item-negative" }
    when /\A-\s+(.+)\z/
      { marker: "•", text: Regexp.last_match(1), list_class: "event-detail-notes-list-neutral", item_class: "event-detail-notes-list-item-neutral" }
    end
  end

  private
    def public_page_slug
      params[:slug].to_s.presence
    end

    def media_url_options
      request_options = {
        protocol: request&.protocol,
        host: request&.host,
        port: request&.optional_port
      }.compact

      request_options.presence || Rails.application.routes.default_url_options
    end
end
