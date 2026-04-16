module Meta
  class ConnectionHealthCheck
    REQUIRED_SCOPES = Meta::Onboarding::AuthorizationUrlBuilder::REQUIRED_SCOPES
    API_VERSION = "v25.0".freeze
    WARNING_WINDOW = 7.days
    REFRESH_WINDOW = 14.days
    REFRESH_RETRY_WINDOW = 6.hours

    def initialize(
      http_client: HttpClient.new,
      page_catalog_fetcher: PageCatalogFetcher.new,
      token_refresher: ConnectionTokenRefresher.new,
      app_id: AppConfig.meta_app_id,
      app_secret: AppConfig.meta_app_secret
    )
      @http_client = http_client
      @page_catalog_fetcher = page_catalog_fetcher
      @token_refresher = token_refresher
      @app_id = app_id.to_s.strip
      @app_secret = app_secret.to_s.strip
    end

    def call(connection: ConnectionResolver.new.connection, refresh: true)
      return missing_connection_status unless connection.present?

      page_target = connection.selected_facebook_page_target
      return missing_page_status(connection) if page_target.blank?

      maybe_refresh_user_token!(connection) if refresh

      checked_at = Time.current
      debug_payload = debug_user_token(connection)
      permissions = permissions_from(debug_payload, connection)
      expires_at = token_expiration_from(debug_payload) || connection.user_token_expires_at
      page_payload = fetch_page_payload(page_target)
      instagram_target = connection.selected_instagram_target
      page_instagram_payload = page_payload["instagram_business_account"] || {}
      missing_permissions = REQUIRED_SCOPES - permissions

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
          instagram_payload: page_instagram_payload
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
          page_payload:,
          instagram_payload: page_instagram_payload
        )
      end

      if instagram_target.present? && page_instagram_payload["id"].to_s.strip != instagram_target.external_id
        return persist_and_build_status(
          connection:,
          connection_status: "error",
          state: :error,
          summary: "Die ausgewählte Facebook-Seite ist nicht mehr mit dem gespeicherten Instagram-Account verknüpft.",
          details: [ "Bitte die Meta-Verbindung prüfen und die Seite erneut auswählen." ],
          checked_at:,
          expires_at:,
          permissions:,
          page_payload:,
          instagram_payload: page_instagram_payload
        )
      end

      if page_instagram_payload["id"].to_s.strip.blank?
        return persist_and_build_status(
          connection:,
          connection_status: "error",
          state: :error,
          summary: "Instagram-Publishing ist nicht möglich, weil zur ausgewählten Facebook-Seite kein Instagram-Professional-Account verknüpft ist.",
          details: [ "Bitte in Meta eine Facebook-Seite auswählen, die direkt mit dem gewünschten Instagram-Professional-Account verbunden ist." ],
          checked_at:,
          expires_at:,
          permissions:,
          page_payload:,
          instagram_payload: page_instagram_payload
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
          instagram_payload: page_instagram_payload
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
          instagram_payload: page_instagram_payload
        )
      end

      persist_and_build_status(
        connection:,
        connection_status: "connected",
        state: :ok,
        summary: "Meta-Verbindung ist gültig.",
        details: [ "Token, Facebook-Seite und Instagram-Verknüpfung wurden erfolgreich geprüft." ],
        checked_at:,
        expires_at:,
        permissions:,
        page_payload:,
        instagram_payload: page_instagram_payload
      )
    rescue Error => error
      persist_and_build_status(
        connection:,
        connection_status: normalized_error_status(error.message),
        state: :error,
        summary: normalized_error_message(error.message),
        details: [ "Publishing wird blockiert, bis die Meta-Verbindung repariert ist." ],
        checked_at: Time.current
      )
    end

    private

    attr_reader :app_id, :app_secret, :http_client, :page_catalog_fetcher, :token_refresher

    def missing_connection_status
      build_status(
        connection_status: "reauth_required",
        state: :error,
        summary: "Meta-Verbindung ist nicht eingerichtet.",
        details: [ "Bitte Facebook und Instagram zuerst mit Meta verbinden." ],
        checked_at: Time.current
      )
    end

    def missing_page_status(connection)
      persist_and_build_status(
        connection:,
        connection_status: "pending_selection",
        state: :error,
        summary: "Es ist noch keine Facebook-Seite ausgewählt.",
        details: [ "Bitte nach dem Login eine Facebook-Seite für das Publishing auswählen." ],
        checked_at: Time.current
      )
    end

    def maybe_refresh_user_token!(connection)
      expires_at = connection.user_token_expires_at
      return unless expires_at.present? && expires_at <= REFRESH_WINDOW.from_now
      return if connection.last_refresh_at.present? && connection.last_refresh_at >= REFRESH_RETRY_WINDOW.ago

      refreshed = token_refresher.call(token: connection.user_access_token)
      connection.update!(
        user_access_token: refreshed.access_token,
        user_token_expires_at: refreshed.expires_at || expires_at,
        last_refresh_at: Time.current,
        connection_status: "connected",
        last_error: nil
      )
      refresh_discovered_pages!(connection)
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
          last_error: nil
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

    def permissions_from(debug_payload, connection)
      Array(debug_payload&.dig("data", "scopes")).compact.presence || connection.granted_scopes
    end

    def token_expiration_from(debug_payload)
      expires_at = debug_payload&.dig("data", "expires_at").to_i
      return if expires_at <= 0

      Time.zone.at(expires_at)
    end

    def normalized_error_message(message)
      case message.to_s
      when /session has expired/i, /error validating access token/i
        "Meta-Token ist abgelaufen oder ungültig."
      when /pages_show_list/i, /pages_read_engagement/i, /pages_manage_posts/i, /instagram_content_publish/i, /instagram_basic/i
        "Meta-Verbindung hat nicht alle nötigen Berechtigungen."
      else
        message.to_s
      end
    end

    def normalized_error_status(message)
      normalized = normalized_error_message(message)
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
      instagram_payload: nil
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
        instagram_payload:
      )
    end

    def sync_selected_targets!(connection:, page_payload:, instagram_payload:, connection_status:)
      page_target = connection.selected_facebook_page_target
      return if page_target.blank?

      page_target.update!(
        name: page_payload&.dig("name").to_s.strip.presence || page_target.name,
        status: connection_status == "connected" || connection_status == "expiring_soon" || connection_status == "refresh_failed" ? "selected" : "error",
        last_synced_at: Time.current,
        last_error: connection_status == "connected" ? nil : connection.last_error
      )

      instagram_target = connection.selected_instagram_target
      return if instagram_target.blank?

      instagram_target.update!(
        username: instagram_payload&.dig("username").to_s.strip.presence || instagram_target.username,
        status: page_target.status,
        last_synced_at: Time.current,
        last_error: page_target.last_error
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
      instagram_payload: nil
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
        debug_available: app_id.present? && app_secret.present?,
        reauth_required: connection_status == "reauth_required",
        payload: {
          "page" => page_payload,
          "instagram_business_account" => instagram_payload
        }.compact
      )
    end
  end
end
