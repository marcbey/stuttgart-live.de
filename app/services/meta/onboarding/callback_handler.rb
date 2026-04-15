module Meta
  module Onboarding
    class CallbackHandler
      ME_FIELDS = "id,name".freeze

      def initialize(
        http_client: HttpClient.new,
        token_refresher: ConnectionTokenRefresher.new,
        page_catalog_fetcher: PageCatalogFetcher.new,
        app_id: AppConfig.meta_app_id,
        app_secret: AppConfig.meta_app_secret
      )
        @http_client = http_client
        @token_refresher = token_refresher
        @page_catalog_fetcher = page_catalog_fetcher
        @app_id = app_id.to_s.strip
        @app_secret = app_secret.to_s.strip
      end

      def call(code:, state:, session:, redirect_uri:)
        ensure_valid_state!(state:, session:)

        short_lived_token, short_lived_expires_at = exchange_code_for_token(code:, redirect_uri:)
        long_lived_token = refresh_user_token(short_lived_token)
        user_profile = fetch_user_profile(long_lived_token.access_token)
        granted_scopes = fetch_granted_scopes(long_lived_token.access_token)
        page_accounts = page_catalog_fetcher.call(user_access_token: long_lived_token.access_token)

        connection = persist_connection!(
          user_profile:,
          token_result: long_lived_token,
          fallback_expires_at: short_lived_expires_at,
          granted_scopes:,
          page_accounts:
        )

        Rails.logger.info(
          "[meta] onboarding callback completed connection_id=#{connection.id} page_count=#{page_accounts.size}"
        )

        connection
      rescue Error => error
        Rails.logger.warn("[meta] onboarding callback failed error=#{error.message}")
        raise
      ensure
        session.delete(AuthorizationUrlBuilder::SESSION_KEY)
      end

      private

      attr_reader :app_id, :app_secret, :http_client, :page_catalog_fetcher, :token_refresher

      def ensure_valid_state!(state:, session:)
        expected_state = session[AuthorizationUrlBuilder::SESSION_KEY].to_s
        provided_state = state.to_s

        raise Error, "Meta-Login konnte nicht verifiziert werden." if expected_state.blank? || provided_state.blank?
        raise Error, "Meta-Login konnte nicht verifiziert werden." unless ActiveSupport::SecurityUtils.secure_compare(expected_state, provided_state)
      end

      def exchange_code_for_token(code:, redirect_uri:)
        payload = http_client.get_json!(
          "https://graph.facebook.com/v25.0/oauth/access_token",
          params: {
            client_id: app_id,
            client_secret: app_secret,
            redirect_uri: redirect_uri,
            code: code
          }
        )

        access_token = payload["access_token"].to_s.strip
        raise Error, "Meta hat kein User-Token zurückgegeben." if access_token.blank?

        expires_in = payload["expires_in"].to_i
        expires_at = expires_in.positive? ? Time.current + expires_in.seconds : nil

        [ access_token, expires_at ]
      end

      def refresh_user_token(short_lived_token)
        token_refresher.call(token: short_lived_token)
      rescue Error
        Struct.new(:access_token, :expires_at).new(short_lived_token, nil)
      end

      def fetch_user_profile(user_access_token)
        http_client.get_json!(
          "https://graph.facebook.com/v25.0/me",
          params: {
            fields: ME_FIELDS,
            access_token: user_access_token
          }
        )
      end

      def fetch_granted_scopes(user_access_token)
        payload = http_client.get_json!(
          "https://graph.facebook.com/v25.0/me/permissions",
          params: {
            access_token: user_access_token
          }
        )

        Array(payload["data"]).filter_map do |entry|
          next unless entry["status"].to_s == "granted"

          entry["permission"].to_s.strip.presence
        end.uniq.sort
      rescue Error
        []
      end

      def persist_connection!(user_profile:, token_result:, fallback_expires_at:, granted_scopes:, page_accounts:)
        SocialConnection.transaction do
          connection = SocialConnection.meta
          connection.assign_attributes(
            auth_mode: "facebook_login_for_business",
            external_user_id: user_profile["id"].to_s.strip.presence,
            user_access_token: token_result.access_token,
            user_token_expires_at: token_result.expires_at || fallback_expires_at,
            granted_scopes: granted_scopes,
            connection_status: page_accounts.any? ? "pending_selection" : "error",
            last_error: page_accounts.any? ? nil : "Keine Facebook Pages gefunden.",
            reauth_required_at: nil,
            metadata: connection.metadata.merge(
              "meta_user_name" => user_profile["name"].to_s.strip.presence,
              "last_page_catalog_sync_at" => Time.current.iso8601
            ).compact
          )
          connection.save!

          sync_page_targets!(connection:, page_accounts:)

          connection
        end
      end

      def sync_page_targets!(connection:, page_accounts:)
        discovered_page_ids = page_accounts.map(&:page_id)

        connection.social_connection_targets.facebook_pages.where.not(external_id: discovered_page_ids).find_each do |target|
          target.update!(selected: false, status: "missing", last_error: "Seite wurde im letzten Onboarding nicht mehr gefunden.")
          target.child_targets.update_all(selected: false, status: "missing", updated_at: Time.current)
        end

        page_accounts.each do |account|
          page_target = connection.social_connection_targets.facebook_pages.find_or_initialize_by(external_id: account.page_id)
          page_target.assign_attributes(
            name: account.page_name,
            access_token: account.page_access_token,
            status: page_target.selected? ? "selected" : "available",
            last_synced_at: Time.current,
            last_error: nil
          )
          page_target.save!

          next if account.instagram_account_id.blank?

          instagram_target = connection.social_connection_targets.instagram_accounts.find_or_initialize_by(
            external_id: account.instagram_account_id
          )
          instagram_target.assign_attributes(
            parent_target: page_target,
            username: account.instagram_username,
            status: instagram_target.selected? ? "selected" : "available",
            selected: instagram_target.selected? && page_target.selected?,
            last_synced_at: Time.current,
            last_error: nil
          )
          instagram_target.save!
        end
      end
    end
  end
end
