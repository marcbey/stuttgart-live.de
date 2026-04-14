require "json"
require "net/http"

module Meta
  class HttpClient
    def post_form!(url, params:)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(stringify_values(params))

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      payload = parse_json(response.body)
      return payload if response.is_a?(Net::HTTPSuccess)

      raise Error, error_message_for(payload, response)
    end

    private

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
