module ApplicationHelper
  def app_nav_link_class(active: false, accent: false)
    classes = [ "app-nav-link" ]
    classes << "app-nav-link-active" if active
    classes << "app-nav-link-accent" if accent
    classes.join(" ")
  end

  def frontend_nav_active?
    controller_path == "public/events"
  end

  def backend_nav_active?
    controller_path == "backend/events"
  end

  def brand_logo_tag(class_name:, alt: "Stuttgart Live", loading: "lazy")
    image_tag(
      "stuttgart-live-logo-modern.svg",
      alt: alt,
      class: class_name,
      loading: loading,
      decoding: "async"
    )
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

  def event_card_image_style(image)
    return nil unless image.is_a?(EventImage)

    [
      "object-position: #{image.card_focus_x_value}% #{image.card_focus_y_value}%",
      "transform: scale(#{(image.card_zoom_value / 100.0).round(3)})",
      "transform-origin: #{image.card_focus_x_value}% #{image.card_focus_y_value}%"
    ].join("; ")
  end
end
