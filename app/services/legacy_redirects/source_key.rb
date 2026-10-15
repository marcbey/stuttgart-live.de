require "uri"

module LegacyRedirects
  class SourceKey
    INTERNAL_PREFIXES = %w[backend rails session passwords login media assets up 400 404 422 500 errors recede_historical_location resume_historical_location refresh_historical_location].freeze
    HOSTS = %w[stuttgart-live.de www.stuttgart-live.de].freeze
    PATH_BYTE = /[A-Za-z0-9\-._~!$&'()*+,;=:@\/]/

    def self.normalize(value, allow_internal: false)
      value = value.to_s
      return unless value.valid_encoding? && !value.match?(/[[:cntrl:]\\]/)

      path, query = extract_path(value)
      return unless path&.start_with?("/") && !path.start_with?("//")
      return unless tracking_query?(query)
      return if path.include?("#") || path.match?(/%(?![0-9a-f]{2})|%(?:2f|5c|0[0-9a-f]|1[0-9a-f]|7f)/i)

      decoded = path.gsub(/%([0-9a-f]{2})/i) { [ $1.to_i(16) ].pack("C") }.force_encoding(Encoding::UTF_8)
      return unless decoded.valid_encoding?
      return if decoded.match?(/[[:cntrl:]\\]/) || decoded.match?(/%(?:25)*(?:2f|5c|2e|00)/i)
      return if decoded.split("/", -1).any? { |part| %w[. ..].include?(part) }
      return if decoded.include?("//")

      canonical = decoded.unicode_normalize(:nfc).bytes.map { |byte| byte.chr.match?(PATH_BYTE) ? byte.chr : format("%%%02X", byte) }.join
      canonical = canonical.delete_suffix("/") unless canonical == "/"
      return if !allow_internal && forbidden?(canonical)

      canonical
    rescue URI::InvalidURIError, ArgumentError, Encoding::CompatibilityError
      nil
    end

    def self.forbidden?(path)
      INTERNAL_PREFIXES.include?(path.split("/", 3)[1].to_s.split(".", 2).first)
    end

    def self.extract_path(value)
      if value.match?(/\Ahttps?:\/\//i)
        uri = URI.parse(value.gsub(/[^\x00-\x7F]/) { |char| char.bytes.map { |byte| format("%%%02X", byte) }.join })
        return unless HOSTS.include?(uri.host&.downcase) && uri.userinfo.nil? && uri.fragment.nil?
        return unless uri.port == uri.default_port

        [ uri.path.presence || "/", uri.query ]
      else
        value.split("?", 2)
      end
    end
    private_class_method :extract_path

    def self.tracking_query?(query)
      return true if query.nil? || query.empty?

      URI.decode_www_form(query).all? { |key, _| key.start_with?("utm_") || %w[gclid fbclid].include?(key) }
    end
    private_class_method :tracking_query?
  end
end
