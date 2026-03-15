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

      def apply_partner_shop_id!(request)
        partner_shop_id = AppConfig.easyticket_partner_shop_id.to_s
        return if partner_shop_id.blank?

        request["partnershopId"] = partner_shop_id
      end
    end
  end
end
