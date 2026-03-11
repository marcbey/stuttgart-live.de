require "digest/md5"
require "json"
require "net/http"

module Newsletter
  class MailchimpClient
    class Error < StandardError; end
    PLACEHOLDER_VALUES = %w[todo tbd changeme change-me replace-me dummy].freeze

    attr_reader :api_key, :audience_id

    def initialize(
      api_key: ENV["MAILCHIMP_API_KEY"].to_s.strip,
      audience_id: ENV["MAILCHIMP_LIST_ID"].to_s.strip.presence || ENV["MAILCHIMP_AUDIENCE_ID"].to_s.strip,
      server_prefix: ENV["MAILCHIMP_SERVER_PREFIX"].to_s.strip
    )
      @api_key = api_key
      @audience_id = audience_id
      @server_prefix = server_prefix
    end

    def configured?
      configured_value?(api_key) && configured_value?(audience_id) && configured_value?(data_center)
    end

    def upsert_member(email:, source:, subscribe_status:)
      raise Error, "Mailchimp is not configured" unless configured?

      uri = member_uri(email)
      request = Net::HTTP::Put.new(uri)
      request.basic_auth("stuttgart-live", api_key)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(
        email_address: email,
        status_if_new: subscribe_status,
        merge_fields: { SOURCE: source.to_s }
      )

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      parse_response(response)
    end

    private

    def member_uri(email)
      URI("https://#{data_center}.api.mailchimp.com/3.0/lists/#{audience_id}/members/#{subscriber_hash(email)}")
    end

    def subscriber_hash(email)
      Digest::MD5.hexdigest(email.to_s.downcase)
    end

    def data_center
      @server_prefix.presence || api_key.split("-").last.to_s.presence
    end

    def configured_value?(value)
      normalized = value.to_s.strip
      normalized.present? && !PLACEHOLDER_VALUES.include?(normalized.downcase)
    end

    def parse_response(response)
      body = response.body.to_s
      payload = body.present? ? JSON.parse(body) : {}
      return payload if response.is_a?(Net::HTTPSuccess)

      message = payload["detail"].presence || payload["title"].presence || "Mailchimp request failed"
      raise Error, message
    rescue JSON::ParserError
      raise Error, "Mailchimp returned invalid JSON"
    end
  end
end
