module Meta
  class ConnectionTokenRefresher
    API_VERSION = "v25.0".freeze
    Result = Data.define(:access_token, :expires_at)

    def initialize(
      http_client: HttpClient.new,
      app_id: AppConfig.meta_app_id,
      app_secret: AppConfig.meta_app_secret
    )
      @http_client = http_client
      @app_id = app_id.to_s.strip
      @app_secret = app_secret.to_s.strip
    end

    def call(token:)
      raise Error, "meta.app_id ist nicht konfiguriert." if app_id.blank?
      raise Error, "meta.app_secret ist nicht konfiguriert." if app_secret.blank?

      payload = http_client.get_json!(
        "https://graph.facebook.com/#{API_VERSION}/oauth/access_token",
        params: {
          client_id: app_id,
          client_secret: app_secret,
          grant_type: "fb_exchange_token",
          fb_exchange_token: token
        }
      )

      refreshed_token = payload["access_token"].to_s.strip
      raise Error, "Meta hat kein erneuertes User-Token zurückgegeben." if refreshed_token.blank?

      expires_in = payload["expires_in"].to_i
      expires_at = expires_in.positive? ? Time.current + expires_in.seconds : nil

      Result.new(access_token: refreshed_token, expires_at:)
    end

    private

    attr_reader :app_id, :app_secret, :http_client
  end
end
