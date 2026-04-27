module Meta
  class FacebookImageRelay
    API_VERSION = "v25.0".freeze

    def initialize(
      http_client: HttpClient.new,
      page_id: nil,
      page_access_token: nil,
      connection_resolver: ConnectionResolver.new
    )
      page_target = connection_resolver.facebook_connection&.selected_facebook_page_target
      @http_client = http_client
      @page_id = page_id.to_s.strip.presence || page_target&.external_id.to_s.strip
      @page_access_token = page_access_token.to_s.strip.presence || page_target&.access_token.to_s.strip
    end

    def relay_image_url(source_url:)
      return if page_id.blank? || page_access_token.blank?

      upload_payload = http_client.post_form!(
        "https://graph.facebook.com/#{API_VERSION}/#{page_id}/photos",
        params: {
          url: source_url,
          published: false,
          access_token: page_access_token
        }
      )

      photo_id = upload_payload["id"].to_s.strip
      raise Error, "Facebook-CDN-Relay hat keine Photo-ID zurückgegeben." if photo_id.blank?

      image_payload = http_client.get_json!(
        "https://graph.facebook.com/#{API_VERSION}/#{photo_id}",
        params: {
          fields: "images",
          access_token: page_access_token
        }
      )

      image_payload.fetch("images", []).filter_map { |image| image["source"].to_s.strip.presence }.first ||
        raise(Error, "Facebook-CDN-Relay hat keine Bild-URL zurückgegeben.")
    end

    private

    attr_reader :http_client, :page_access_token, :page_id
  end
end
