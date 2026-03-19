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
      "transform: scale(#{(image.card_zoom_value / 100.0).round(3)})",
      "transform-origin: #{image.card_focus_x_value}% #{image.card_focus_y_value}%"
    ].join("; ")
  end

  def optimized_event_image_representation(image)
    return if image.blank?
    return image unless image.is_a?(EventImage)

    image.processed_optimized_variant
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

  def blog_post_image_style(blog_post, slot)
    focus_x = blog_post.public_send("#{slot}_focus_x_value")
    focus_y = blog_post.public_send("#{slot}_focus_y_value")
    zoom = blog_post.public_send("#{slot}_zoom_value")

    [
      "object-position: #{focus_x}% #{focus_y}%",
      "transform: scale(#{(zoom / 100.0).round(3)})",
      "transform-origin: #{focus_x}% #{focus_y}%"
    ].join("; ")
  end

  def optimized_blog_post_image_representation(blog_post, slot)
    return unless blog_post.present?

    attachment = blog_post.public_send(slot)
    return attachment unless attachment.attached?

    blog_post.processed_optimized_image_variant(slot)
  end

  def blog_post_cropped_image_style(blog_post, slot, frame_ratio:)
    image = blog_post.public_send(slot)
    metadata = image&.attached? ? image.blob.metadata : {}
    image_width = metadata["width"].to_f
    image_height = metadata["height"].to_f

    return blog_post_image_style(blog_post, slot) unless image_width.positive? && image_height.positive?

    focus_x = blog_post.public_send("#{slot}_focus_x_value") / 100.0
    focus_y = blog_post.public_send("#{slot}_focus_y_value") / 100.0
    zoom_scale = blog_post.public_send("#{slot}_zoom_value") / 100.0
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

  def blog_post_image_copyright(blog_post, slot)
    blog_post.public_send("#{slot}_copyright")
  end

  def formatted_organizer_notes(notes)
    formatted_organizer_notes_with_link(notes)
  end

  private

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
