require "json"
require "net/http"
require "cgi"

module Meta
  class HttpClient
    def get_json!(url, params: {})
      uri = URI.parse(url)
      existing_query = URI.decode_www_form(String(uri.query))
      uri.query = URI.encode_www_form(existing_query + stringify_values(params).to_a)

      request = Net::HTTP::Get.new(uri)
      perform!(uri, request)
    end

    def post_form!(url, params:)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(stringify_values(params))

      perform!(uri, request)
    end

    private

    def perform!(uri, request)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      payload = parse_json(response.body)
      return payload if response.is_a?(Net::HTTPSuccess)

      raise Error, error_message_for(payload, response)
    end

    def stringify_values(params)
      params.compact.transform_values(&:to_s)
    end

    def parse_json(body)
      JSON.parse(body.to_s.presence || "{}")
    rescue JSON::ParserError
      {}
    end

    def error_message_for(payload, response)
      payload.dig("error", "message").presence ||
        payload["error_description"].presence ||
        payload["message"].presence ||
        "Meta-Request fehlgeschlagen (HTTP #{response.code})"
    end
  end
end
