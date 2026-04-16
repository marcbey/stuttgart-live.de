module Meta
  module Onboarding
    class InstagramAccountFetcher
      API_VERSION = "v25.0".freeze
      ACCOUNT_FIELDS = "id,user_id,username,account_type,name,profile_picture_url".freeze

      def initialize(http_client: HttpClient.new)
        @http_client = http_client
      end

      def call(user_access_token:)
        payload = http_client.get_json!(
          "https://graph.instagram.com/#{API_VERSION}/me",
          params: {
            fields: ACCOUNT_FIELDS,
            access_token: user_access_token
          }
        )

        instagram_account_id = payload["user_id"].to_s.strip.presence
        raise Error, "Instagram-Professional-Account konnte nicht geladen werden." if instagram_account_id.blank?

        payload
      end

      private

      attr_reader :http_client
    end
  end
end
