module Meta
  module Onboarding
    class InstagramCallbackHandler
      def initialize(
        http_client: HttpClient.new,
        token_refresher: ConnectionTokenRefresher.new,
        instagram_account_fetcher: InstagramAccountFetcher.new,
        app_id: AppConfig.meta_instagram_app_id,
        app_secret: AppConfig.meta_instagram_app_secret
      )
        @http_client = http_client
        @token_refresher = token_refresher
        @instagram_account_fetcher = instagram_account_fetcher
        @app_id = app_id.to_s.strip
        @app_secret = app_secret.to_s.strip
      end

      def call(code:, state:, session:, redirect_uri:)
        ensure_valid_state!(state:, session:)

        short_lived_token, short_lived_expires_at, permissions = exchange_code_for_token(code:, redirect_uri:)
        long_lived_token = refresh_user_token(short_lived_token)
        account_profile = instagram_account_fetcher.call(user_access_token: long_lived_token.access_token)

        connection = persist_connection!(
          account_profile:,
          token_result: long_lived_token,
          fallback_expires_at: short_lived_expires_at,
          granted_scopes: permissions
        )

        Rails.logger.info(
          "[meta] instagram onboarding callback completed connection_id=#{connection.id} instagram_account_id=#{account_profile['user_id']}"
        )

        connection
      rescue Error => error
        Rails.logger.warn("[meta] instagram onboarding callback failed error=#{error.message}")
        raise
      ensure
        session.delete(InstagramAuthorizationUrlBuilder::SESSION_KEY)
      end

      private

      attr_reader :app_id, :app_secret, :http_client, :instagram_account_fetcher, :token_refresher

      def ensure_valid_state!(state:, session:)
        expected_state = session[InstagramAuthorizationUrlBuilder::SESSION_KEY].to_s
        provided_state = state.to_s

        raise Error, "Instagram-Login konnte nicht verifiziert werden." if expected_state.blank? || provided_state.blank?
        raise Error, "Instagram-Login konnte nicht verifiziert werden." unless ActiveSupport::SecurityUtils.secure_compare(expected_state, provided_state)
      end

      def exchange_code_for_token(code:, redirect_uri:)
        payload = http_client.post_form!(
          "https://api.instagram.com/oauth/access_token",
          params: {
            client_id: app_id,
            client_secret: app_secret,
            grant_type: "authorization_code",
            redirect_uri: redirect_uri,
            code: code
          }
        )

        access_token = payload["access_token"].to_s.strip
        raise Error, "Instagram hat kein User-Token zurückgegeben." if access_token.blank?

        expires_in = payload["expires_in"].to_i
        expires_at = expires_in.positive? ? Time.current + expires_in.seconds : nil
        permissions = Array(payload["permissions"]).filter_map { |permission| permission.to_s.strip.presence }.uniq.sort

        [ access_token, expires_at, permissions ]
      end

      def refresh_user_token(short_lived_token)
        token_refresher.call(token: short_lived_token, auth_mode: "instagram_login")
      rescue Error
        Struct.new(:access_token, :expires_at).new(short_lived_token, nil)
      end

      def persist_connection!(account_profile:, token_result:, fallback_expires_at:, granted_scopes:)
        SocialConnection.transaction do
          connection = SocialConnection.meta
          connection.assign_attributes(
            auth_mode: "instagram_login",
            external_user_id: account_profile["id"].to_s.strip.presence,
            user_access_token: token_result.access_token,
            user_token_expires_at: token_result.expires_at || fallback_expires_at,
            granted_scopes: granted_scopes.presence || InstagramAuthorizationUrlBuilder::REQUIRED_SCOPES,
            connection_status: "connected",
            connected_at: connection.connected_at || Time.current,
            last_error: nil,
            reauth_required_at: nil,
            metadata: connection.metadata.to_h.merge(
              "instagram_user_id" => account_profile["user_id"].to_s.strip.presence,
              "instagram_username" => account_profile["username"].to_s.strip.presence,
              "instagram_account_type" => account_profile["account_type"].to_s.strip.presence,
              "instagram_name" => account_profile["name"].to_s.strip.presence,
              "instagram_profile_picture_url" => account_profile["profile_picture_url"].to_s.strip.presence,
              "last_instagram_sync_at" => Time.current.iso8601
            ).compact
          )
          connection.save!

          sync_instagram_target!(connection:, account_profile:)

          connection
        end
      end

      def sync_instagram_target!(connection:, account_profile:)
        instagram_account_id = account_profile["user_id"].to_s.strip

        connection.social_connection_targets.instagram_accounts.where.not(external_id: instagram_account_id).find_each do |target|
          target.update!(
            selected: false,
            status: "missing",
            last_error: "Instagram-Account wurde im letzten Onboarding nicht mehr gefunden."
          )
        end

        target = connection.social_connection_targets.instagram_accounts.find_or_initialize_by(external_id: instagram_account_id)
        target.update!(
          username: account_profile["username"].to_s.strip.presence,
          name: account_profile["name"].to_s.strip.presence,
          status: "selected",
          selected: true,
          parent_target: nil,
          access_token: nil,
          last_synced_at: Time.current,
          last_error: nil,
          metadata: target.metadata.to_h.merge(
            "account_type" => account_profile["account_type"].to_s.strip.presence,
            "profile_picture_url" => account_profile["profile_picture_url"].to_s.strip.presence
          ).compact
        )

        connection.social_connection_targets.facebook_pages.selected.update_all(
          selected: false,
          status: "available",
          updated_at: Time.current
        )
      end
    end
  end
end
