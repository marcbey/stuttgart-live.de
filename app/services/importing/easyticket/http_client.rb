require "net/http"
require "uri"

module Importing
  module Easyticket
    class HttpClient
      OPEN_TIMEOUT_SECONDS = 30
      READ_TIMEOUT_SECONDS = 60

      def get(url, accept: nil)
        uri = URI.parse(url)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = accept if accept.present?
        apply_basic_auth!(request)
        apply_api_key!(request)
        apply_partner_shop_id!(request)

        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT_SECONDS,
          read_timeout: READ_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise RequestError, "Request failed for #{uri} with status #{response.code}"
        end

        response.body.to_s
      end

      private

      def apply_basic_auth!(request)
        user = ENV["EASYTICKET_USER"].to_s
        pass = ENV["EASYTICKET_PASS"].to_s
        return if user.blank? || pass.blank?

        request.basic_auth(user, pass)
      end

      def apply_api_key!(request)
        api_key = ENV["EASYTICKET_API_KEY"].to_s
        return if api_key.blank?

        request["X-API-Key"] = api_key
      end

      def apply_partner_shop_id!(request)
        partner_shop_id = ENV["EASYTICKET_PARTNER_SHOP_ID"].to_s
        return if partner_shop_id.blank?

        request["partnershopid"] = partner_shop_id
      end
    end
  end
end
