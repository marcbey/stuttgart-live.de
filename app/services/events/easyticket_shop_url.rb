require "uri"

module Events
  class EasyticketShopUrl
    OWN_SHOP_ID = "3b38659fef6bcc38e100c728435ba8e9".freeze
    GENERAL_SHOP_ID = "c2b3ee865fb7464a68403f97966923d8".freeze
    HOSTS = %w[easyticket.de www.easyticket.de partnershop.easyticket.de].freeze
    MUSIC_CIRCUS_IDS = { "easyticket" => "141", "eventim" => "36" }.freeze
    OWN_PROMOTER_NAME = /\b(?:music\s+circus|michael\s+russ|russ\s+live)\b/i

    def initialize(url:, event:)
      @url = url
      @event = event
    end

    def call
      uri = URI.parse(@url)
      return @url unless uri.is_a?(URI::HTTP) && HOSTS.include?(uri.host.to_s.downcase)

      path = shop_path(uri)
      return @url unless path

      shop_id = own_promoter? ? OWN_SHOP_ID : GENERAL_SHOP_ID
      uri.scheme = "https"
      uri.host = "partnershop.easyticket.de"
      uri.port = 443
      uri.path = "/#{shop_id}#{path}"
      uri.to_s
    rescue URI::InvalidURIError
      @url
    end

    private

    def shop_path(uri)
      return if uri.path.start_with?("/files/") || uri.path.match?(/\.pdf\z/i)

      if uri.host.casecmp?("partnershop.easyticket.de") && uri.path.match?(%r{\A/[a-f0-9]{32}(?:/|\z)}i)
        return uri.path.sub(%r{\A/[a-f0-9]{32}}i, "")
      end

      return "" if uri.path.blank? || uri.path == "/"

      event_id = uri.path[%r{/([0-9]+)/?\z}, 1]
      event_id ? "/event/#{event_id}" : ""
    end

    def own_promoter?
      return false unless @event
      return true if @event.sks_promoter?
      return true if own_source?(@event.primary_source, @event.promoter_id, @event.promoter_name)

      Array(@event.source_snapshot.to_h["sources"]).any? do |source|
        own_source?(source["source"], source["promoter_id"], source["promoter_name"])
      end
    end

    def own_source?(source, promoter_id, promoter_name)
      return true if promoter_name.to_s.match?(OWN_PROMOTER_NAME)
      return true if AppSetting.sks_promoter_ids.include?(promoter_id.to_s)

      music_circus_id = MUSIC_CIRCUS_IDS[source.presence || "easyticket"]
      music_circus_id.present? && promoter_id.to_s == music_circus_id
    end
  end
end
