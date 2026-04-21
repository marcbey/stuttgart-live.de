module Meta
  class ConnectionHealthCheck
    API_VERSION = "v25.0".freeze
    WARNING_WINDOW = 7.days
    REFRESH_WINDOW = 14.days
    REFRESH_RETRY_WINDOW = 6.hours
    INSTAGRAM_ACCOUNT_FIELDS = "id,user_id,username,account_type,name,profile_picture_url".freeze
    INSTAGRAM_ACCOUNT_TYPES = %w[BUSINESS MEDIA_CREATOR].freeze

    def initialize(
      http_client: HttpClient.new,
      page_catalog_fetcher: PageCatalogFetcher.new,
      token_refresher: ConnectionTokenRefresher.new,
      app_id: AppConfig.meta_app_id.presence || AppConfig.meta_instagram_app_id,
      app_secret: AppConfig.meta_app_secret.presence || AppConfig.meta_instagram_app_secret
    )
      @http_client = http_client
      @page_catalog_fetcher = page_catalog_fetcher
      @token_refresher = token_refresher
      @app_id = app_id.to_s.strip
      @app_secret = app_secret.to_s.strip
    end

    def call(connection: ConnectionResolver.new.connection, refresh: true)
      return missing_connection_status unless connection.present?

      connection.instagram_login? ? instagram_login_status(connection:, refresh:) : facebook_login_status(connection:, refresh:)
    rescue Error => error
      persist_and_build_status(
        connection:,
        connection_status: normalized_error_status(error.message),
        state: :error,
        summary: normalized_error_message(error.message),
        details: [ "Publishing wird blockiert, bis die Meta-Verbindung repariert ist." ],
        checked_at: Time.current,
        auth_mode: connection&.auth_mode
      )
    end

    private

    attr_reader :app_id, :app_secret, :http_client, :page_catalog_fetcher, :token_refresher

    def instagram_login_status(connection:, refresh:)
      maybe_refresh_user_token!(connection) if refresh

      checked_at = Time.current
      permissions = Array(connection.granted_scopes)
      expires_at = connection.user_token_expires_at
      instagram_payload = fetch_instagram_payload(connection)
      missing_permissions = required_scopes_for(connection) - permissions

      if missing_permissions.any?
        return persist_and_build_status(
          connection:,
          connection_status: "reauth_required",
          state: :error,
          summary: "Instagram-Verbindung hat nicht alle nötigen Berechtigungen.",
          details: [ "Es fehlen folgende Scopes: #{missing_permissions.join(', ')}." ],
          checked_at:,
          expires_at:,
          permissions:,
          instagram_payload:,
          auth_mode: connection.auth_mode
        )
      end

      if expires_at.present? && expires_at <= Time.current
        return persist_and_build_status(
          connection:,
          connection_status: "reauth_required",
          state: :error,
          summary: "Instagram-Token ist abgelaufen oder ungültig.",
          details: [ "Bitte die Instagram-Verbindung erneut herstellen." ],
          checked_at:,
          expires_at:,
          permissions:,
          instagram_payload:,
          auth_mode: connection.auth_mode
        )
      end

      if invalid_instagram_account_type?(instagram_payload["account_type"])
        return persist_and_build_status(
          connection:,
          connection_status: "error",
          state: :error,
          summary: "Instagram-Publishing ist nur mit einem Professional-Account möglich.",
          details: [ "Bitte in Instagram zu einem Business- oder Creator-Account wechseln." ],
          checked_at:,
          expires_at:,
          permissions:,
          instagram_payload:,
          auth_mode: connection.auth_mode
        )
      end

      selected_instagram_target = connection.selected_instagram_target
      remote_instagram_id = instagram_payload["user_id"].to_s.strip
      if selected_instagram_target.present? && remote_instagram_id != selected_instagram_target.external_id
        return persist_and_build_status(
          connection:,
          connection_status: "error",
          state: :error,
          summary: "Der verbundene Instagram-Account stimmt nicht mehr mit dem gespeicherten Publish-Ziel überein.",
          details: [ "Bitte die Instagram-Verbindung erneut herstellen." ],
          checked_at:,
          expires_at:,
          permissions:,
          instagram_payload:,
          auth_mode: connection.auth_mode
        )
      end

      if expires_at.present? && expires_at <= WARNING_WINDOW.from_now
        return persist_and_build_status(
          connection:,
          connection_status: "expiring_soon",
          state: :warning,
          summary: "Instagram-Token läuft bald ab.",
          details: [ "Publishing funktioniert aktuell noch, aber die Verbindung sollte zeitnah erneuert werden." ],
          checked_at:,
          expires_at:,
          permissions:,
          instagram_payload:,
          auth_mode: connection.auth_mode
        )
      end

      if connection.refresh_failed?
        return persist_and_build_status(
          connection:,
          connection_status: "refresh_failed",
          state: :warning,
          summary: "Instagram-Token konnte zuletzt nicht serverseitig verlängert werden.",
          details: [ "Die Verbindung ist aktuell noch nutzbar, sollte aber vorsorglich neu verbunden werden." ],
          checked_at:,
          expires_at:,
          permissions:,
          instagram_payload:,
          auth_mode: connection.auth_mode
        )
      end

      persist_and_build_status(
        connection:,
        connection_status: "connected",
        state: :ok,
        summary: "Instagram-Verbindung ist gültig.",
        details: [ "Token und Instagram-Professional-Account wurden erfolgreich geprüft." ],
        checked_at:,
        expires_at:,
        permissions:,
        instagram_payload:,
        auth_mode: connection.auth_mode
      )
    end

    def facebook_login_status(connection:, refresh:)
      page_target = connection.selected_facebook_page_target
      maybe_refresh_user_token!(connection) if refresh

      checked_at = Time.current
      debug_payload = debug_user_token(connection)
      permissions = permissions_from(debug_payload, connection)
      expires_at = token_expiration_from(debug_payload) || connection.user_token_expires_at
      page_accounts = page_catalog_fetcher.call(user_access_token: connection.user_access_token)
      selected_instagram_target = connection.selected_instagram_target
      missing_permissions = required_scopes_for(connection) - permissions

      if missing_permissions.any?
        return persist_and_build_status(
          connection:,
          connection_status: "reauth_required",
          state: :error,
          summary: "Meta-Verbindung hat nicht alle nötigen Berechtigungen.",
          details: [ "Es fehlen folgende Scopes: #{missing_permissions.join(', ')}." ],
          checked_at:,
          expires_at:,
          permissions:,
          page_payload:,
          instagram_payload: page_instagram_payload,
          auth_mode: connection.auth_mode
        )
      end

      if expires_at.present? && expires_at <= Time.current
        return persist_and_build_status(
          connection:,
          connection_status: "reauth_required",
          state: :error,
          summary: "Meta-Token ist abgelaufen oder ungültig.",
          details: [ "Bitte die Meta-Verbindung erneut herstellen." ],
          checked_at:,
          expires_at:,
          permissions:,
          auth_mode: connection.auth_mode
        )
      end

      if selected_instagram_target.blank?
        return persist_and_build_status(
          connection:,
          connection_status: "error",
          state: :error,
          summary: "Für die Meta-Verbindung ist noch kein eindeutiger Instagram-Professional-Account ausgewählt.",
          details: [ "Bitte in Meta Publishing eine Facebook-Seite mit verknüpftem Instagram-Professional-Account auswählen." ],
          checked_at:,
          expires_at:,
          permissions:,
          auth_mode: connection.auth_mode
        )
      end

      if page_target.blank?
        unless page_accounts.any? { |account| account.instagram_account_id == selected_instagram_target.external_id }
          return persist_and_build_status(
            connection:,
            connection_status: "error",
            state: :error,
            summary: "Der gespeicherte Instagram-Professional-Account ist in der aktuellen Meta-Verbindung nicht mehr verfügbar.",
            details: [ "Bitte die Meta-Verbindung erneut herstellen oder eine passende Facebook-Seite auswählen." ],
            checked_at:,
            expires_at:,
            permissions:,
            instagram_payload: {
              "id" => selected_instagram_target.external_id,
              "username" => selected_instagram_target.username
            },
            auth_mode: connection.auth_mode
          )
        end

        return persist_and_build_status(
          connection:,
          connection_status: "pending_selection",
          state: :warning,
          summary: "Instagram-Verbindung ist gültig. Für direktes Facebook-Publishing ist noch keine Facebook-Seite ausgewählt.",
          details: [ "Instagram-Publishing ist möglich. Für zusätzliches Facebook-Publishing bitte eine Facebook-Seite auswählen." ],
          checked_at:,
          expires_at:,
          permissions:,
          instagram_payload: {
            "id" => selected_instagram_target.external_id,
            "username" => selected_instagram_target.username
          },
          auth_mode: connection.auth_mode
        )
      end

      page_payload = fetch_page_payload(page_target)
      page_instagram_payload = page_payload["instagram_business_account"] || {}

      if page_instagram_payload["id"].to_s.strip.blank?
        return persist_and_build_status(
          connection:,
          connection_status: "error",
          state: :error,
          summary: "Die ausgewählte Facebook-Seite ist nicht mit einem Instagram-Professional-Account verknüpft.",
          details: [ "Bitte in Meta Publishing eine andere Facebook-Seite auswählen oder die Seitenverknüpfung in Meta korrigieren." ],
          checked_at:,
          expires_at:,
          permissions:,
          page_payload:,
          instagram_payload: page_instagram_payload,
          auth_mode: connection.auth_mode
        )
      end

      if page_instagram_payload["id"].to_s.strip != selected_instagram_target.external_id
        return persist_and_build_status(
          connection:,
          connection_status: "error",
          state: :error,
          summary: "Die ausgewählte Facebook-Seite passt nicht zum gespeicherten Instagram-Professional-Account.",
          details: [ "Bitte die Meta-Verbindung prüfen und die Facebook-Seite erneut auswählen." ],
          checked_at:,
          expires_at:,
          permissions:,
          page_payload:,
          instagram_payload: page_instagram_payload,
          auth_mode: connection.auth_mode
        )
      end

      if expires_at.present? && expires_at <= WARNING_WINDOW.from_now
        return persist_and_build_status(
          connection:,
          connection_status: "expiring_soon",
          state: :warning,
          summary: "Meta-Token läuft bald ab.",
          details: [ "Publishing funktioniert aktuell noch, aber die Verbindung sollte zeitnah erneuert werden." ],
          checked_at:,
          expires_at:,
          permissions:,
          page_payload:,
          instagram_payload: page_instagram_payload,
          auth_mode: connection.auth_mode
        )
      end

      if connection.refresh_failed?
        return persist_and_build_status(
          connection:,
          connection_status: "refresh_failed",
          state: :warning,
          summary: "Meta-Token konnte zuletzt nicht serverseitig verlängert werden.",
          details: [ "Die Verbindung ist aktuell noch nutzbar, sollte aber vorsorglich neu verbunden werden." ],
          checked_at:,
          expires_at:,
          permissions:,
          page_payload:,
          instagram_payload: page_instagram_payload,
          auth_mode: connection.auth_mode
        )
      end

      persist_and_build_status(
        connection:,
        connection_status: "connected",
        state: :ok,
        summary: "Meta-Verbindung ist gültig.",
        details: [ "Token, Legacy-Facebook-Seite und Instagram-Verknüpfung wurden erfolgreich geprüft." ],
        checked_at:,
        expires_at:,
        permissions:,
        page_payload:,
        instagram_payload: page_instagram_payload,
        auth_mode: connection.auth_mode
      )
    end

    def missing_connection_status
      build_status(
        connection_status: "reauth_required",
        state: :error,
        summary: "Instagram-Verbindung ist nicht eingerichtet.",
        details: [ "Bitte Instagram zuerst mit Meta verbinden." ],
        checked_at: Time.current,
        auth_mode: "instagram_login"
      )
    end

    def missing_page_status(connection)
      persist_and_build_status(
        connection:,
        connection_status: "pending_selection",
        state: :warning,
        summary: "Es ist noch keine Facebook-Seite ausgewählt.",
        details: [ "Instagram-Publishing bleibt möglich. Für direktes Facebook-Publishing bitte eine Facebook-Seite auswählen." ],
        checked_at: Time.current,
        auth_mode: connection.auth_mode
      )
    end

    def maybe_refresh_user_token!(connection)
      expires_at = connection.user_token_expires_at
      return unless expires_at.present? && expires_at <= REFRESH_WINDOW.from_now
      return if connection.last_refresh_at.present? && connection.last_refresh_at >= REFRESH_RETRY_WINDOW.ago

      refreshed = token_refresher.call(token: connection.user_access_token, auth_mode: connection.auth_mode)
      connection.update!(
        user_access_token: refreshed.access_token,
        user_token_expires_at: refreshed.expires_at || expires_at,
        last_refresh_at: Time.current,
        connection_status: "connected",
        last_error: nil
      )
      refresh_discovered_pages!(connection) if connection.facebook_login_for_business?
    rescue Error => error
      connection.update!(
        last_refresh_at: Time.current,
        connection_status: "refresh_failed",
        last_error: normalized_error_message(error.message)
      )
      Rails.logger.warn("[meta] token refresh failed connection_id=#{connection.id} error=#{error.message}")
    end

    def refresh_discovered_pages!(connection)
      page_accounts = page_catalog_fetcher.call(user_access_token: connection.user_access_token)

      page_accounts.each do |account|
        target = connection.social_connection_targets.facebook_pages.find_or_initialize_by(external_id: account.page_id)
        target.update!(
          name: account.page_name,
          access_token: account.page_access_token,
          status: target.selected? ? "selected" : "available",
          last_synced_at: Time.current,
          last_error: nil,
          metadata: target.metadata.to_h.merge(
            "instagram_account_id" => account.instagram_account_id,
            "instagram_username" => account.instagram_username
          ).compact
        )
      end
    end

    def debug_user_token(connection)
      return if app_id.blank? || app_secret.blank?

      payload = http_client.get_json!(
        "https://graph.facebook.com/#{API_VERSION}/debug_token",
        params: {
          input_token: connection.user_access_token,
          access_token: "#{app_id}|#{app_secret}"
        }
      )

      data = payload["data"] || {}
      raise Error, "Meta-Token ist abgelaufen oder ungültig." unless data["is_valid"]

      payload
    end

    def fetch_page_payload(page_target)
      raise Error, "Für die ausgewählte Facebook-Seite fehlt ein Page-Access-Token." if page_target.access_token.blank?

      payload = http_client.get_json!(
        "https://graph.facebook.com/#{API_VERSION}/#{page_target.external_id}",
        params: {
          fields: "id,name,instagram_business_account{id,username}",
          access_token: page_target.access_token
        }
      )

      resolved_page_id = payload["id"].to_s.strip
      raise Error, "Meta-Seite konnte nicht mit dem gespeicherten Page-Token aufgelöst werden." if resolved_page_id.blank?
      raise Error, "Meta-Seite stimmt nicht mit der gespeicherten Auswahl überein." if resolved_page_id != page_target.external_id

      payload
    end

    def fetch_instagram_payload(connection)
      payload = http_client.get_json!(
        "https://graph.instagram.com/#{API_VERSION}/me",
        params: {
          fields: INSTAGRAM_ACCOUNT_FIELDS,
          access_token: connection.user_access_token
        }
      )

      instagram_account_id = payload["user_id"].to_s.strip
      raise Error, "Instagram-Professional-Account konnte nicht geladen werden." if instagram_account_id.blank?

      payload
    end

    def permissions_from(debug_payload, connection)
      Array(debug_payload&.dig("data", "scopes")).compact.presence || connection.granted_scopes
    end

    def token_expiration_from(debug_payload)
      expires_at = debug_payload&.dig("data", "expires_at").to_i
      return if expires_at <= 0

      Time.zone.at(expires_at)
    end

    def required_scopes_for(connection)
      if connection.instagram_login?
        Meta::Onboarding::InstagramAuthorizationUrlBuilder::REQUIRED_SCOPES
      else
        Meta::Onboarding::AuthorizationUrlBuilder::REQUIRED_SCOPES
      end
    end

    def invalid_instagram_account_type?(account_type)
      normalized_account_type = account_type.to_s.strip.upcase
      normalized_account_type.present? && !INSTAGRAM_ACCOUNT_TYPES.include?(normalized_account_type)
    end

    def normalized_error_message(message)
      case message.to_s
      when /session has expired/i, /error validating access token/i, /expired/i
        "Instagram-Token ist abgelaufen oder ungültig."
      when /instagram_business_basic/i, /instagram_business_content_publish/i
        "Instagram-Verbindung hat nicht alle nötigen Berechtigungen."
      when /pages_show_list/i, /pages_read_engagement/i, /pages_manage_posts/i, /instagram_content_publish/i, /instagram_basic/i
        "Meta-Verbindung hat nicht alle nötigen Berechtigungen."
      else
        message.to_s
      end
    end

    def normalized_error_status(message)
      normalized = normalized_error_message(message)
      return "reauth_required" if normalized == "Instagram-Token ist abgelaufen oder ungültig."
      return "reauth_required" if normalized == "Instagram-Verbindung hat nicht alle nötigen Berechtigungen."
      return "reauth_required" if normalized == "Meta-Token ist abgelaufen oder ungültig."
      return "reauth_required" if normalized == "Meta-Verbindung hat nicht alle nötigen Berechtigungen."

      "error"
    end

    def persist_and_build_status(
      connection: nil,
      connection_status:,
      state:,
      summary:,
      details:,
      checked_at:,
      expires_at: nil,
      permissions: [],
      page_payload: nil,
      instagram_payload: nil,
      auth_mode: nil
    )
      if connection.present?
        connection.update!(
          connection_status:,
          user_token_expires_at: expires_at || connection.user_token_expires_at,
          granted_scopes: permissions.presence || connection.granted_scopes,
          last_token_check_at: checked_at,
          reauth_required_at: connection_status == "reauth_required" ? checked_at : nil,
          last_error: state == :ok ? nil : summary
        )

        sync_selected_targets!(
          connection:,
          page_payload:,
          instagram_payload:,
          connection_status:
        )
      end

      build_status(
        connection:,
        connection_status:,
        state:,
        summary:,
        details:,
        checked_at:,
        expires_at:,
        permissions:,
        page_payload:,
        instagram_payload:,
        auth_mode: auth_mode || connection&.auth_mode
      )
    end

    def sync_selected_targets!(connection:, page_payload:, instagram_payload:, connection_status:)
      selected_status =
        if %w[connected expiring_soon refresh_failed pending_selection].include?(connection_status)
          "selected"
        else
          "error"
        end

      if connection.facebook_login_for_business?
        page_target = connection.selected_facebook_page_target
        if page_target.present?
          page_target.update!(
            name: page_payload&.dig("name").to_s.strip.presence || page_target.name,
            status: selected_status,
            last_synced_at: Time.current,
            last_error: connection_status == "connected" ? nil : connection.last_error
          )
        end
      end

      instagram_target = connection.selected_instagram_target
      return if instagram_target.blank?

      instagram_target.update!(
        username: instagram_payload&.dig("username").to_s.strip.presence || instagram_target.username,
        name: instagram_payload&.dig("name").to_s.strip.presence || instagram_target.name,
        status: selected_status,
        last_synced_at: Time.current,
        last_error: connection_status == "connected" ? nil : connection.last_error,
        metadata: instagram_target.metadata.to_h.merge(
          "account_type" => instagram_payload&.dig("account_type").to_s.strip.presence,
          "profile_picture_url" => instagram_payload&.dig("profile_picture_url").to_s.strip.presence
        ).compact
      )
    end

    def build_status(
      connection: nil,
      connection_status:,
      state:,
      summary:,
      details:,
      checked_at:,
      expires_at: nil,
      permissions: [],
      page_payload: nil,
      instagram_payload: nil,
      auth_mode: nil
    )
      AccessStatus::Status.new(
        connection_status:,
        state:,
        summary:,
        details: Array(details),
        checked_at:,
        expires_at:,
        page_name: page_payload&.dig("name").to_s.strip.presence || connection&.selected_facebook_page_target&.name,
        instagram_username: instagram_payload&.dig("username").to_s.strip.presence || connection&.selected_instagram_target&.username,
        permissions:,
        debug_available: auth_mode.to_s == "facebook_login_for_business" ? app_id.present? && app_secret.present? : true,
        reauth_required: connection_status == "reauth_required",
        payload: {
          "auth_mode" => auth_mode,
          "page" => page_payload,
          "instagram_account" => instagram_payload
        }.compact
      )
    end
  end
end
