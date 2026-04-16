module Meta
  class InstagramPublisher
    Result = Data.define(:remote_media_id, :remote_post_id, :payload)
    API_VERSION = "v25.0".freeze
    PUBLISHING_STATUS_FIELDS = "id,status_code".freeze

    def initialize(
      http_client: HttpClient.new,
      instagram_account_id: nil,
      user_access_token: nil,
      connection_resolver: ConnectionResolver.new
    )
      connection = connection_resolver.connection
      instagram_target = connection&.selected_instagram_target
      @http_client = http_client
      @instagram_account_id = instagram_account_id.to_s.strip.presence || instagram_target&.external_id.to_s.strip
      @user_access_token = user_access_token.to_s.strip.presence || connection&.user_access_token.to_s.strip
    end

    def publish!(event_social_post:)
      ensure_configured!

      container_payload = http_client.post_form!(
        "https://graph.instagram.com/#{API_VERSION}/#{instagram_account_id}/media",
        params: {
          image_url: event_social_post.publish_image_url_for("instagram"),
          caption: event_social_post.caption,
          access_token: user_access_token
        }
      )

      container_id = container_payload["id"].to_s.strip
      raise Error, "Instagram hat keinen Media-Container zurückgegeben." if container_id.blank?

      publish_payload = http_client.post_form!(
        "https://graph.instagram.com/#{API_VERSION}/#{instagram_account_id}/media_publish",
        params: {
          creation_id: container_id,
          access_token: user_access_token
        }
      )

      remote_media_id = publish_payload["id"].to_s.strip.presence
      if remote_media_id.blank?
        container_status = fetch_container_status(container_id)
        raise Error, missing_media_id_message(container_status)
      end

      media_payload = fetch_media_payload(remote_media_id)

      Result.new(
        remote_media_id: remote_media_id,
        remote_post_id: nil,
        payload: {
          "container" => container_payload,
          "publish" => publish_payload,
          "media" => media_payload
        }
      )
    end

    private

    attr_reader :http_client, :instagram_account_id, :user_access_token

    def ensure_configured!
      raise Error, "Es ist kein Instagram-Professional-Account für das Publishing verbunden." if instagram_account_id.blank?
      raise Error, "Für das Instagram-Publishing fehlt ein gültiges User-Token." if user_access_token.blank?
    end

    def fetch_media_payload(remote_media_id)
      http_client.get_json!(
        "https://graph.instagram.com/#{API_VERSION}/#{remote_media_id}",
        params: {
          fields: "id,permalink",
          access_token: user_access_token
        }
      )
    rescue Error
      {}
    end

    def fetch_container_status(container_id)
      http_client.get_json!(
        "https://graph.instagram.com/#{API_VERSION}/#{container_id}",
        params: {
          fields: PUBLISHING_STATUS_FIELDS,
          access_token: user_access_token
        }
      )
    rescue Error
      {}
    end

    def missing_media_id_message(container_status)
      status_code = container_status["status_code"].to_s.strip.presence
      return "Instagram hat keine Media-ID zurückgegeben." if status_code.blank?

      "Instagram hat keine Media-ID zurückgegeben (Container-Status: #{status_code})."
    end
  end
end
