module Backend
  class MetaConnectionsController < BaseController
    before_action :require_admin!

    def show
      redirect_to edit_backend_settings_path(section: "meta_connection")
    end

    def start
      start_facebook
    end

    def start_instagram
      Meta::Onboarding::Configuration.new.ensure_configured!

      authorization_url = Meta::Onboarding::InstagramAuthorizationUrlBuilder.new.call(
        session:,
        redirect_uri: callback_url(flow_label: "Instagram")
      )

      redirect_to authorization_url, allow_other_host: true
    rescue Meta::Error => error
      redirect_to edit_backend_settings_path(section: "meta_connection"), alert: error.message
    end

    def start_facebook
      Meta::Onboarding::Configuration.new.ensure_configured!

      authorization_url = Meta::Onboarding::AuthorizationUrlBuilder.new.call(
        session:,
        redirect_uri: callback_url(flow_label: "Facebook")
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

      connection =
        if session[Meta::Onboarding::InstagramAuthorizationUrlBuilder::SESSION_KEY].present?
          Meta::Onboarding::InstagramCallbackHandler.new.call(
            code: params[:code].to_s,
            state: params[:state].to_s,
            session:,
            redirect_uri: callback_url(flow_label: "Meta")
          )
        else
          Meta::Onboarding::CallbackHandler.new.call(
            code: params[:code].to_s,
            state: params[:state].to_s,
            session:,
            redirect_uri: callback_url(flow_label: "Meta")
          )
        end

      notice =
        if connection.platform == "instagram"
          "Instagram-Verbindung ist aktiv."
        elsif connection.selected_facebook_page_target.present?
          "Facebook-Verbindung ist aktiv. Facebook-Seite wurde gespeichert."
        elsif connection.selected_instagram_target.present?
          "Meta-Verbindung wurde hergestellt. Instagram ist aktiv, für direktes Facebook-Publishing bitte noch eine Facebook-Seite auswählen."
        else
          "Facebook-Verbindung wurde hergestellt. Für Publishing muss jetzt eine Facebook-Seite ausgewählt werden."
        end

      redirect_to edit_backend_settings_path(section: "meta_connection"), notice: notice
    rescue Meta::Error => error
      redirect_to edit_backend_settings_path(section: "meta_connection"), alert: error.message
    end

    def select_target
      connection = Meta::ConnectionResolver.new.connection_for!("facebook")

      facebook_target = connection.social_connection_targets.facebook_pages.find(params[:target_id])
      connection = Meta::Onboarding::PageSelection.new.call(connection:, facebook_target:)

      notice =
        if connection.selected_facebook_page_target.present?
          "Facebook-Verbindung ist aktiv. Facebook-Seite wurde gespeichert."
        else
          "Facebook-Verbindung ist unvollständig. Bitte eine Facebook-Seite auswählen."
        end

      flash_type = connection.selected_facebook_page_target.present? ? :notice : :alert
      redirect_to edit_backend_settings_path(section: "meta_connection"), flash_type => notice
    rescue ActiveRecord::RecordNotFound
      redirect_to edit_backend_settings_path(section: "meta_connection"), alert: "Facebook-Page-Auswahl ist ungültig."
    rescue Meta::Error => error
      redirect_to edit_backend_settings_path(section: "meta_connection"), alert: error.message
    end

    def refresh_status
      Meta::AccessStatus.new(platform: "instagram").call(force: true)
      Meta::AccessStatus.new(platform: "facebook").call(force: true)
      redirect_to edit_backend_settings_path(section: "meta_connection"), notice: "Meta-Status wurde aktualisiert."
    rescue Meta::Error => error
      redirect_to edit_backend_settings_path(section: "meta_connection"), alert: error.message
    end

    private

    def callback_error_message
      params[:error_description].to_s.strip.presence || "Meta-Onboarding wurde abgebrochen."
    end

    def callback_url(flow_label:)
      configured_redirect_uri = AppConfig.meta_instagram_redirect_uri
      if configured_redirect_uri.present?
        ensure_redirect_uri_matches_request!(configured_redirect_uri, flow_label:)
        return configured_redirect_uri
      end

      callback_backend_meta_connection_url(
        host: request.host,
        port: request.optional_port,
        protocol: request.protocol
      )
    end

    def ensure_redirect_uri_matches_request!(configured_redirect_uri, flow_label:)
      configured_uri = URI.parse(configured_redirect_uri)
      configured_origin = origin_for(configured_uri.scheme, configured_uri.host, optional_port_for(configured_uri))
      request_origin = origin_for(request.protocol.delete_suffix("://"), request.host, request.optional_port)

      return if configured_origin == request_origin

      raise Meta::Error,
        "#{flow_label}-Onboarding muss auf #{configured_origin} gestartet werden, weil meta.instagram_redirect_uri auf diesen Host konfiguriert ist."
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
