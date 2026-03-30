module ApplicationHelper
  GOOGLE_ANALYTICS_ALLOWED_HOSTS = %w[
    stuttgart-live.de
    www.stuttgart-live.de
  ].freeze

  def app_nav_link_class(active: false, accent: false)
    classes = [ "app-nav-link" ]
    classes << "app-nav-link-active" if active
    classes << "app-nav-link-accent" if accent
    classes.join(" ")
  end

  def events_nav_active?
    controller_path == "public/events"
  end

  def news_nav_active?
    controller_path == "public/news"
  end

  def contact_nav_active?
    controller_path == "public/pages" && action_name == "contact"
  end

  def imprint_nav_active?
    controller_path == "public/pages" && action_name == "imprint"
  end

  def backend_nav_active?
    controller_path == "backend/events"
  end

  def blog_nav_active?
    controller_path == "backend/blog_posts"
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
    manifest_assets =
      if Rails.application.respond_to?(:assets_manifest)
        Rails.application.assets_manifest&.assets
      end
    return true if manifest_assets&.key?(logical_path)

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

  def optimized_event_image_source(image)
    return if image.blank?
    return image.image_url unless image.is_a?(EventImage)

    rails_storage_proxy_path(optimized_event_image_representation(image), only_path: true)
  end

  def optimized_event_image_url(image)
    return if image.blank?
    return image.image_url unless image.is_a?(EventImage)

    rails_storage_proxy_url(optimized_event_image_representation(image))
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

  def optimized_event_promotion_banner_image_source(event)
    representation = optimized_event_promotion_banner_image_representation(event)
    return if representation.blank?

    rails_storage_proxy_path(representation, only_path: true)
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

    rails_storage_proxy_path(representation, only_path: true)
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

    rails_storage_proxy_path(representation, only_path: true)
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

    url_for(representation)
  end

  def blog_post_cropped_image_style(blog_post, slot, frame_ratio:)
    cropped_attachment_style(
      attachment: blog_post.public_send(slot),
      focus_x: blog_post.public_send("#{slot}_focus_x_value"),
      focus_y: blog_post.public_send("#{slot}_focus_y_value"),
      zoom: blog_post.public_send("#{slot}_zoom_value"),
      frame_ratio: frame_ratio,
      fallback_style: focused_cropped_fallback_style(
        focus_x: blog_post.public_send("#{slot}_focus_x_value"),
        focus_y: blog_post.public_send("#{slot}_focus_y_value"),
        zoom: blog_post.public_send("#{slot}_zoom_value")
      )
    )
  end

  def blog_post_image_copyright(blog_post, slot)
    blog_post.public_send("#{slot}_copyright")
  end

  def formatted_organizer_notes(notes)
    formatted_organizer_notes_with_link(notes)
  end

  private

  def focused_image_style(focus_x:, focus_y:, zoom:)
    [
      "object-position: #{focus_x}% #{focus_y}%",
      "transform: scale(#{(zoom.to_f / 100.0).round(3)})",
      "transform-origin: #{focus_x}% #{focus_y}%"
    ].join("; ")
  end

  def focused_cropped_fallback_style(focus_x:, focus_y:, zoom:)
    zoom_scale = zoom.to_f / 100.0
    offset_x = 0.5 - ((focus_x.to_f / 100.0) * zoom_scale)
    offset_y = 0.5 - ((focus_y.to_f / 100.0) * zoom_scale)

    [
      "position: absolute",
      "left: #{(offset_x * 100).round(3)}%",
      "top: #{(offset_y * 100).round(3)}%",
      "width: #{(zoom_scale * 100).round(3)}%",
      "height: #{(zoom_scale * 100).round(3)}%",
      "object-fit: fill",
      "max-width: none",
      "max-height: none"
    ].join("; ")
  end

  def cropped_attachment_style(attachment:, focus_x:, focus_y:, zoom:, frame_ratio:, fallback_style:)
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

    [
      "position: absolute",
      "left: #{(offset_x * 100).round(3)}%",
      "top: #{(offset_y * 100).round(3)}%",
      "width: #{(width_factor * 100).round(3)}%",
      "height: #{(height_factor * 100).round(3)}%",
      "object-fit: fill",
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
    escaped = ERB::Util.html_escape(notes.to_s)
    phrase = "(Das Begleitformular findest Du HIER)"
    begleitformular_link = link_to(
      "<span class=\"inline-arrow\">→</span> Begleitformular <span class=\"inline-file-badge\">PDF</span>".html_safe,
      begleitformular_path(
        event: [ event&.artist_name, event&.title ].compact.join(" - ").presence,
        venue: event&.venue,
        date: event&.start_at&.to_date&.iso8601
      )
    )

    simple_format(escaped.gsub(phrase, begleitformular_link).html_safe)
  end
end
