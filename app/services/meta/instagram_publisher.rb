module Meta
  class InstagramPublisher
    Result = Data.define(:remote_media_id, :remote_post_id, :payload)
    API_VERSION = "v25.0".freeze

    def initialize(
      http_client: HttpClient.new,
      instagram_business_account_id: nil,
      page_access_token: nil,
      connection_resolver: ConnectionResolver.new
    )
      connection = connection_resolver.connection
      instagram_target = connection&.selected_instagram_target
      page_target = connection&.selected_facebook_page_target
      @http_client = http_client
      @instagram_business_account_id = instagram_business_account_id.to_s.strip.presence || instagram_target&.external_id.to_s.strip
      @page_access_token = page_access_token.to_s.strip.presence || page_target&.access_token.to_s.strip
    end

    def publish!(event_social_post:)
      ensure_configured!

      container_payload = http_client.post_form!(
        "https://graph.facebook.com/#{API_VERSION}/#{instagram_business_account_id}/media",
        params: {
          image_url: event_social_post.publish_image_url_for("instagram"),
          caption: event_social_post.caption,
          access_token: page_access_token
        }
      )

      container_id = container_payload["id"].to_s.strip
      raise Error, "Instagram hat keinen Media-Container zurückgegeben." if container_id.blank?

      publish_payload = http_client.post_form!(
        "https://graph.facebook.com/#{API_VERSION}/#{instagram_business_account_id}/media_publish",
        params: {
          creation_id: container_id,
          access_token: page_access_token
        }
      )

      remote_media_id = publish_payload["id"].to_s.strip.presence
      raise Error, "Instagram hat keine Media-ID zurückgegeben." if remote_media_id.blank?

      Result.new(
        remote_media_id: remote_media_id,
        remote_post_id: nil,
        payload: {
          "container" => container_payload,
          "publish" => publish_payload
        }
      )
    end

    private

    attr_reader :http_client, :instagram_business_account_id, :page_access_token

    def ensure_configured!
      raise Error, "Für die ausgewählte Facebook-Seite ist kein Instagram-Professional-Account verknüpft." if instagram_business_account_id.blank?
      raise Error, "Für die ausgewählte Facebook-Seite fehlt ein Page-Access-Token." if page_access_token.blank?
    end
  end
end
