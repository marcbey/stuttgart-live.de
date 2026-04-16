module Backend
  class MetaConnectionsController < BaseController
    before_action :require_admin!

    def show
      redirect_to edit_backend_settings_path(section: "meta_connection")
    end

    def start
      Meta::Onboarding::Configuration.new.ensure_configured!

      authorization_url = Meta::Onboarding::InstagramAuthorizationUrlBuilder.new.call(
        session:,
        redirect_uri: callback_url
      )

      redirect_to authorization_url, allow_other_host: true
    rescue Meta::Error => error
      redirect_to edit_backend_settings_path(section: "meta_connection"), alert: error.message
    end

    def callback
      if params[:error].present?
        redirect_to edit_backend_settings_path(section: "meta_connection"), alert: callback_error_message
        return
      end

      connection = Meta::Onboarding::InstagramCallbackHandler.new.call(
        code: params[:code].to_s,
        state: params[:state].to_s,
        session:,
        redirect_uri: callback_url
      )

      redirect_to edit_backend_settings_path(section: "meta_connection"),
        notice: "Instagram-Verbindung wurde hergestellt. Facebook-Cross-Posting wird weiterhin ausschließlich direkt in Meta konfiguriert."
    rescue Meta::Error => error
      redirect_to edit_backend_settings_path(section: "meta_connection"), alert: error.message
    end

    def select_target
      connection = Meta::ConnectionResolver.new.connection!
      if connection.instagram_login?
        redirect_to edit_backend_settings_path(section: "meta_connection"),
          alert: "Im Instagram-Login-Modus ist keine Facebook-Seitenauswahl nötig."
        return
      end

      facebook_target = connection.social_connection_targets.facebook_pages.find(params[:target_id])
      connection = Meta::Onboarding::PageSelection.new.call(connection:, facebook_target:)

      notice =
        if connection.selected_instagram_target.present?
          "Meta-Verbindung ist aktiv. Facebook-Seite und Instagram-Professional-Account wurden gespeichert."
        else
          "Meta-Verbindung ist unvollständig. Für die gewählte Facebook-Seite wurde kein verknüpfter Instagram-Professional-Account gefunden."
        end

      flash_type = connection.selected_instagram_target.present? ? :notice : :alert
      redirect_to edit_backend_settings_path(section: "meta_connection"), flash_type => notice
    rescue ActiveRecord::RecordNotFound
      redirect_to edit_backend_settings_path(section: "meta_connection"), alert: "Facebook-Page-Auswahl ist ungültig."
    rescue Meta::Error => error
      redirect_to edit_backend_settings_path(section: "meta_connection"), alert: error.message
    end

    def refresh_status
      Meta::AccessStatus.new.call(force: true)
      redirect_to edit_backend_settings_path(section: "meta_connection"), notice: "Meta-Status wurde aktualisiert."
    rescue Meta::Error => error
      redirect_to edit_backend_settings_path(section: "meta_connection"), alert: error.message
    end

    private

    def callback_error_message
      params[:error_description].to_s.strip.presence || "Instagram-Onboarding wurde abgebrochen."
    end

    def callback_url
      configured_redirect_uri = AppConfig.meta_instagram_redirect_uri
      if configured_redirect_uri.present?
        ensure_redirect_uri_matches_request!(configured_redirect_uri)
        return configured_redirect_uri
      end

      callback_backend_meta_connection_url(
        host: request.host,
        port: request.optional_port,
        protocol: request.protocol
      )
    end

    def ensure_redirect_uri_matches_request!(configured_redirect_uri)
      configured_uri = URI.parse(configured_redirect_uri)
      configured_origin = origin_for(configured_uri.scheme, configured_uri.host, optional_port_for(configured_uri))
      request_origin = origin_for(request.protocol.delete_suffix("://"), request.host, request.optional_port)

      return if configured_origin == request_origin

      raise Meta::Error,
        "Instagram-Onboarding muss auf #{configured_origin} gestartet werden, weil meta.instagram_redirect_uri auf diesen Host konfiguriert ist."
    rescue URI::InvalidURIError
      raise Meta::Error, "meta.instagram_redirect_uri ist ungültig."
    end

    def origin_for(protocol, host, port)
      suffix = port.present? ? ":#{port}" : ""
      "#{protocol}://#{host}#{suffix}"
    end

    def optional_port_for(uri)
      default_port =
        case uri.scheme
        when "https" then 443
        when "http" then 80
        end

      uri.port == default_port ? nil : uri.port
    end
  end
end
