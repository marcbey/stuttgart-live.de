module Meta
  module Onboarding
    class PageSelection
      API_VERSION = "v25.0".freeze

      def initialize(http_client: HttpClient.new)
        @http_client = http_client
      end

      def call(connection:, facebook_target:)
        raise Error, "Meta-Verbindung ist nicht eingerichtet." if connection.blank?
        raise Error, "Facebook-Page-Auswahl ist ungültig." if facebook_target.blank? || !facebook_target.facebook_page?
        raise Error, "Facebook-Page-Auswahl ist ungültig." unless facebook_target.social_connection_id == connection.id

        page_payload = fetch_page_payload(facebook_target)
        instagram_payload = page_payload["instagram_business_account"] || {}

        SocialConnection.transaction do
          reset_previous_selection!(connection)

          facebook_target.update!(
            name: page_payload["name"].to_s.strip.presence || facebook_target.name,
            selected: true,
            status: "selected",
            last_synced_at: Time.current,
            last_error: nil,
            metadata: facebook_target.metadata.to_h.merge(
              "instagram_account_id" => instagram_payload["id"].to_s.strip.presence,
              "instagram_username" => instagram_payload["username"].to_s.strip.presence
            ).compact
          )

          connection.update!(
            connection_status: "connected",
            connected_at: connection.connected_at || Time.current,
            last_error: nil,
            reauth_required_at: nil
          )
        end

        Rails.logger.info(
          "[meta] selected page connection_id=#{connection.id} page_id=#{facebook_target.external_id}"
        )

        connection.reload
      rescue Error => error
        Rails.logger.warn(
          "[meta] page selection failed connection_id=#{connection&.id} page_id=#{facebook_target&.external_id} error=#{error.message}"
        )
        raise
      end

      private

      attr_reader :http_client

      def fetch_page_payload(facebook_target)
        raise Error, "Für die gewählte Facebook-Seite fehlt ein Page-Access-Token." if facebook_target.access_token.blank?

        http_client.get_json!(
          "https://graph.facebook.com/#{API_VERSION}/#{facebook_target.external_id}",
          params: {
            fields: "id,name,instagram_business_account{id,username}",
            access_token: facebook_target.access_token
          }
        )
      end

      def reset_previous_selection!(connection)
        connection.social_connection_targets.selected.find_each do |target|
          target.update!(selected: false, status: "available")
        end
      end
    end
  end
end
