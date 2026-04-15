require "ipaddr"

module Meta
  class PublicUrlGuard
    LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

    def self.public_url?(value)
      new.public_url?(value)
    end

    def public_url?(value)
      uri = URI.parse(value.to_s)
      return false unless uri.is_a?(URI::HTTP) && uri.host.present?
      return false if LOCAL_HOSTS.include?(uri.host.downcase)

      ip_address = IPAddr.new(uri.host)
      return false if ip_address.private?
      return false if ip_address.loopback?

      true
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError
      true
    end
  end
end
