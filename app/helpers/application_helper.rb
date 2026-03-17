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

  def formatted_organizer_notes(notes)
    formatted_organizer_notes_with_link(notes)
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
