module Backend
  class MetaConnectionsController < BaseController
    before_action :require_admin!

    def show
      redirect_to edit_backend_settings_path(section: "meta_connection")
    end

    def start
      Meta::Onboarding::Configuration.new.ensure_configured!

      authorization_url = Meta::Onboarding::AuthorizationUrlBuilder.new.call(
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

      connection = Meta::Onboarding::CallbackHandler.new.call(
        code: params[:code].to_s,
        state: params[:state].to_s,
        session:,
        redirect_uri: callback_url
      )

      notice =
        if connection.social_connection_targets.facebook_pages.any?
          "Meta-Verbindung wurde hergestellt. Bitte jetzt die Facebook-Seite auswählen."
        else
          "Meta-Login war erfolgreich, aber es wurden keine Facebook Pages gefunden."
        end

      redirect_to edit_backend_settings_path(section: "meta_connection"), notice:
    rescue Meta::Error => error
      redirect_to edit_backend_settings_path(section: "meta_connection"), alert: error.message
    end

    def select_target
      connection = Meta::ConnectionResolver.new.connection!
      facebook_target = connection.social_connection_targets.facebook_pages.find(params[:target_id])
      connection = Meta::Onboarding::PageSelection.new.call(connection:, facebook_target:)

      notice =
        if connection.selected_instagram_target.present?
          "Meta-Verbindung ist aktiv. Facebook-Seite und Instagram-Account wurden gespeichert."
        else
          "Meta-Verbindung ist aktiv. Für die gewählte Facebook-Seite wurde kein Instagram-Professional-Account gefunden."
        end

      redirect_to edit_backend_settings_path(section: "meta_connection"), notice:
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
      params[:error_description].to_s.strip.presence || "Meta-Onboarding wurde abgebrochen."
    end

    def callback_url
      callback_backend_meta_connection_url(
        host: request.host,
        port: request.optional_port,
        protocol: request.protocol
      )
    end
  end
end
