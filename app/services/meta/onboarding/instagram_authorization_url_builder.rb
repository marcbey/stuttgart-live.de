require "securerandom"

module Meta
  module Onboarding
    class InstagramAuthorizationUrlBuilder
      SESSION_KEY = :meta_instagram_oauth_state
      REQUIRED_SCOPES = %w[
        instagram_business_basic
        instagram_business_content_publish
      ].freeze
      AUTH_BASE_URL = "https://www.instagram.com/oauth/authorize".freeze

      def initialize(app_id: AppConfig.meta_instagram_app_id)
        @app_id = app_id.to_s.strip
      end

      def call(session:, redirect_uri:)
        raise Error, "meta.instagram_app_id ist nicht konfiguriert." if app_id.blank?

        state = SecureRandom.hex(24)
        session[SESSION_KEY] = state

        query = {
          client_id: app_id,
          redirect_uri: redirect_uri,
          state: state,
          response_type: "code",
          scope: REQUIRED_SCOPES.join(","),
          force_reauth: "true",
          enable_fb_login: "false"
        }

        "#{AUTH_BASE_URL}?#{URI.encode_www_form(query)}"
      end

      private

      attr_reader :app_id
    end
  end
end
