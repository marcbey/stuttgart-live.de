module Public::VideosHelper
  def public_event_video_playlist(events, attachments:, browse_state:, strict_proxy: false)
    events.flat_map do |event|
      attachments.filter_map do |attachment_name|
        attachment = event.public_send(attachment_name)
        next unless attachment.attached?

        portrait = attachment_name == :highlight_video_file
        {
          src: public_media_path(attachment),
          poster: event_image_source(event.event_image, strict_proxy: strict_proxy, size: :banner_mobile),
          href: public_event_detail_path(event, browse_state),
          label: "#{event.artist_name.presence || event.title} ansehen",
          title: event.promotion_banner_title_value,
          subtitle: event.title,
          date: l(event.start_at.to_date, format: "%d.%m.%Y"),
          location: event.venue,
          overlay: portrait && event.highlight_video_overlay_enabled?,
          adminHref: (backend_events_path(status: event.status, event_id: event.id) if authenticated?),
          orientation: portrait ? "portrait" : "landscape"
        }
      end
    end.uniq { |entry| entry.fetch(:src) }
  end

  def public_homepage_highlight_playlist(events:, browse_state:, setting:, strict_proxy: false, fallback_video: nil, fallback_poster: nil, fallback_href: nil)
    playlist = public_event_video_playlist(events, attachments: [ :highlight_video_file ], browse_state: browse_state, strict_proxy: strict_proxy)
    return playlist if playlist.any?
    return [] unless setting.homepage_highlight_video_enabled

    uploaded = setting.homepage_highlight_video_file.attached?
    source = uploaded ? public_media_path(setting.homepage_highlight_video_file) : fallback_video
    return [] if source.blank?

    config = setting.homepage_highlight_video_config
    [ {
      src: source,
      poster: setting.homepage_highlight_video_poster_image.attached? ? public_media_path(setting.homepage_highlight_video_poster_image) : fallback_poster,
      href: (fallback_href unless uploaded),
      label: "Highlight-Video ansehen",
      title: config.fetch("title"), subtitle: config.fetch("subtitle"),
      date: config.fetch("date"), location: config.fetch("location"),
      overlay: setting.homepage_highlight_video_overlay_enabled,
      adminHref: (edit_backend_settings_path(section: "homepage_highlight_video") if authenticated?),
      orientation: "portrait"
    } ]
  end

  def public_homepage_landscape_playlist(events:, browse_state:, strict_proxy: false)
    playlist = public_event_video_playlist(events, attachments: [ :highlight_landscape_video_file ], browse_state: browse_state, strict_proxy: strict_proxy)
    return playlist if playlist.any?

    [ {
      src: asset_path("design_preview/mamma-mia-highlight.mp4"),
      poster: asset_path("design_preview/mamma-mia-highlight-poster.jpg"),
      href: event_path("mamma-mia-das-musical-2027-05-05", **browse_state.route_params),
      label: "MAMMA MIA! – Das Musical ansehen",
      overlay: false, orientation: "landscape"
    } ]
  end
end
