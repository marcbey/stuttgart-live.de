require "cgi"
require "json"

module Importing
  module Easyticket
    class DetailFetcher
      def initialize(
        http_client: HttpClient.new,
        event_detail_api: ENV["EVENT_DETAIL_API"],
        api_key: ENV["API_KEY"],
        partner_shop_id: ENV["PARTNER_SHOP_ID"]
      )
        @http_client = http_client
        @event_detail_api = event_detail_api.to_s
        @api_key = api_key.to_s
        @partner_shop_id = partner_shop_id.to_s
      end

      def fetch(event_id)
        body = @http_client.get(build_detail_url(event_id), accept: "application/json")
        parsed = JSON.parse(body)
        parsed.is_a?(Hash) ? parsed.deep_stringify_keys : { "data" => parsed }
      rescue JSON::ParserError => e
        raise ParsingError, "Could not parse Easyticket detail payload for event_id=#{event_id}: #{e.message}"
      end

      private

      def build_detail_url(event_id)
        raise Error, "EVENT_DETAIL_API is not configured" if @event_detail_api.blank?

        escaped_event_id = CGI.escape(event_id.to_s)
        escaped_api_key = CGI.escape(@api_key)
        escaped_partner_shop_id = CGI.escape(@partner_shop_id)

        url = interpolate_template(
          @event_detail_api,
          event_id: escaped_event_id,
          api_key: escaped_api_key,
          partner_shop_id: escaped_partner_shop_id
        )
        if url == @event_detail_api
          url = "#{@event_detail_api.chomp('/')}/#{escaped_event_id}"
        end

        append_api_key(url)
      end

      def append_api_key(url)
        return url if @api_key.blank?
        return url if url.include?("api_key=")

        delimiter = url.include?("?") ? "&" : "?"
        "#{url}#{delimiter}api_key=#{CGI.escape(@api_key)}"
      end

      def interpolate_template(template, values)
        rendered = template.dup

        values.each do |key, value|
          rendered = rendered.gsub("%{#{key}}", value.to_s)
          rendered = rendered.gsub("{#{key}}", value.to_s)
        end

        if rendered.match?(/%\{[^}]+\}|\{[a-z_]+\}/i)
          raise Error, "EVENT_DETAIL_API uses unsupported placeholder"
        end

        rendered
      end
    end
  end
end
