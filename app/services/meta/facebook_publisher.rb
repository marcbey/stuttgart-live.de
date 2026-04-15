module Meta
  class FacebookPublisher
    Result = Data.define(:remote_media_id, :remote_post_id, :payload)
    API_VERSION = "v25.0".freeze

    def initialize(
      http_client: HttpClient.new,
      page_id: nil,
      page_access_token: nil,
      connection_resolver: ConnectionResolver.new
    )
      page_target = connection_resolver.connection&.selected_facebook_page_target
      @http_client = http_client
      @page_id = page_id.to_s.strip.presence || page_target&.external_id.to_s.strip
      @page_access_token = page_access_token.to_s.strip.presence || page_target&.access_token.to_s.strip
    end

    def publish!(event_social_post:)
      ensure_configured!

      payload = http_client.post_form!(
        "https://graph.facebook.com/#{API_VERSION}/#{page_id}/photos",
        params: {
          url: event_social_post.publish_image_url_for("facebook"),
          message: event_social_post.caption,
          published: true,
          access_token: page_access_token
        }
      )

      remote_media_id = payload["id"].to_s.strip.presence
      remote_post_id = payload["post_id"].to_s.strip.presence || remote_media_id
      raise Error, "Facebook hat keine Beitrags-ID zurückgegeben." if remote_post_id.blank?

      Result.new(
        remote_media_id:,
        remote_post_id:,
        payload: payload.merge("post_url" => post_url_for(remote_post_id))
      )
    end

    private

    attr_reader :http_client, :page_access_token, :page_id

    def ensure_configured!
      raise Error, "Es ist keine Facebook-Seite für Meta ausgewählt." if page_id.blank?
      raise Error, "Für die ausgewählte Facebook-Seite fehlt ein Page-Access-Token." if page_access_token.blank?
    end

    def post_url_for(remote_post_id)
      page_id_part, post_id_part = remote_post_id.to_s.split("_", 2)
      return if page_id_part.blank? || post_id_part.blank?

      "https://www.facebook.com/#{page_id_part}/posts/#{post_id_part}"
    end
  end
end
