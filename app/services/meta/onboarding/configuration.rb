module Meta
  module Onboarding
    class Configuration
      def initialize(
        app_id: AppConfig.meta_instagram_app_id,
        app_secret: AppConfig.meta_instagram_app_secret,
        credentials: Rails.application.credentials
      )
        @app_id = app_id.to_s.strip
        @app_secret = app_secret.to_s.strip
        @credentials = credentials
      end

      def ensure_configured!
        raise Error, "meta.instagram_app_id ist nicht konfiguriert." if app_id.blank?
        raise Error, "meta.instagram_app_secret ist nicht konfiguriert." if app_secret.blank?
        raise Error, "active_record_encryption ist nicht vollständig konfiguriert." unless active_record_encryption_configured?
      end

      private

      attr_reader :app_id, :app_secret, :credentials

      def active_record_encryption_configured?
        credentials.dig(:active_record_encryption, :primary_key).to_s.strip.present? &&
          credentials.dig(:active_record_encryption, :deterministic_key).to_s.strip.present? &&
          credentials.dig(:active_record_encryption, :key_derivation_salt).to_s.strip.present?
      end
    end
  end
end
