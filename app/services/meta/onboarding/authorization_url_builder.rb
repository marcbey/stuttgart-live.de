require "securerandom"

module Meta
  module Onboarding
    class AuthorizationUrlBuilder
      SESSION_KEY = :meta_oauth_state
      REQUIRED_SCOPES = %w[
        pages_show_list
        pages_read_engagement
        pages_manage_posts
        instagram_basic
        instagram_content_publish
      ].freeze
      AUTH_BASE_URL = "https://www.facebook.com/v25.0/dialog/oauth".freeze

      def initialize(app_id: AppConfig.meta_app_id.presence || AppConfig.meta_instagram_app_id)
        @app_id = app_id.to_s.strip
      end

      def call(session:, redirect_uri:)
        raise Error, "meta.app_id oder meta.instagram_app_id ist nicht konfiguriert." if app_id.blank?

        state = SecureRandom.hex(24)
        session[SESSION_KEY] = state

        query = {
          client_id: app_id,
          redirect_uri: redirect_uri,
          state: state,
          response_type: "code",
          scope: REQUIRED_SCOPES.join(",")
        }

        "#{AUTH_BASE_URL}?#{URI.encode_www_form(query)}"
      end

      private

      attr_reader :app_id
    end
  end
end
