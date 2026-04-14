module Meta
  class InstagramPublisher
    Result = Data.define(:remote_media_id, :remote_post_id, :payload)
    API_VERSION = "v25.0".freeze

    def initialize(
      http_client: HttpClient.new,
      instagram_business_account_id: AppConfig.meta_instagram_business_account_id,
      page_access_token: AppConfig.meta_facebook_page_access_token
    )
      @http_client = http_client
      @instagram_business_account_id = instagram_business_account_id.to_s.strip
      @page_access_token = page_access_token.to_s.strip
    end

    def publish!(event_social_post:)
      ensure_configured!

      container_payload = http_client.post_form!(
        "https://graph.facebook.com/#{API_VERSION}/#{instagram_business_account_id}/media",
        params: {
          image_url: event_social_post.image_url,
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
      raise Error, "meta.instagram_business_account_id ist nicht konfiguriert." if instagram_business_account_id.blank?
      raise Error, "meta.facebook_page_access_token ist nicht konfiguriert." if page_access_token.blank?
    end
  end
end
