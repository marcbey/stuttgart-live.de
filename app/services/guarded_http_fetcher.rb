require "net/http"
require "resolv"
require "ipaddr"

class GuardedHttpFetcher
  class Error < StandardError; end
  class DeadlineExceeded < StandardError; end
  Response = Data.define(:url, :status, :content_type, :body)
  HTML_LIMIT = 2.megabytes
  MEDIA_LIMIT = 25.megabytes
  BLOCKED_NETWORKS = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8].map { |range| IPAddr.new(range) }.freeze
  NETWORK_ERRORS = [ Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError ].freeze

  def initialize(dns: ->(host) { Resolv.getaddresses(host) }, transport: nil, interval: 0.5, retries: 2, max_redirects: 5, total_timeout: 30)
    @dns, @transport = dns, transport || method(:request)
    @interval, @retries, @max_redirects = interval, retries, max_redirects
    @total_timeout = total_timeout
  end

  def call(url, max_bytes: HTML_LIMIT, allowed: nil)
    ExternalActionPolicy.require_allowed!(action: :external_import)
    Timeout.timeout(@total_timeout, DeadlineExceeded) { fetch_redirects(url, max_bytes:, allowed:) }
  rescue *NETWORK_ERRORS, DeadlineExceeded, URI::InvalidURIError, KeyError => error
    raise Error, error.class.name, cause: nil
  end

  private

  def fetch_redirects(url, max_bytes:, allowed:)
    uri = validated_uri(url)
    (@max_redirects + 1).times do
      raise Error, "URL blocked by robots" if allowed && !allowed.call(uri.to_s)
      addresses = @dns.call(uri.host)
      raise Error, "Unsafe or missing DNS address" if addresses.empty? || addresses.any? { |address| unsafe_address?(address) }

      response = fetch(uri, addresses.first, max_bytes)
      status, headers, body = response.values_at(:status, :headers, :body)
      raise Error, "Response too large" if body.bytesize > max_bytes
      if [ 301, 302, 303, 307, 308 ].include?(status)
        uri = validated_uri(URI.join(uri.to_s, headers.fetch("location")).to_s)
        next
      end
      raise Error, "HTTP #{status}" unless status == 200

      return Response.new(url: uri.to_s, status: status, content_type: headers["content-type"].to_s.split(";").first, body: body)
    end
    raise Error, "Too many redirects"
  rescue *NETWORK_ERRORS, URI::InvalidURIError, KeyError => error
    raise Error, error.class.name, cause: nil
  end

  def validated_uri(url)
    uri = URI.parse(url)
    unless %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil? && uri.port == uri.default_port && uri.fragment.nil?
      raise Error, "Unsafe URL"
    end
    uri
  end

  def unsafe_address?(address)
    ip = IPAddr.new(address)
    ip = ip.native if ip.ipv4_mapped?
    BLOCKED_NETWORKS.any? { |network| network.include?(ip) } || (ip.ipv6? && !IPAddr.new("2000::/3").include?(ip))
  rescue IPAddr::InvalidAddressError
    true
  end

  def fetch(uri, address, max_bytes)
    attempts = 0
    begin
      wait = @interval - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - (@last_request || 0))
      sleep(wait) if wait.positive?
      @last_request = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @transport.call(uri, ip: address, max_bytes: max_bytes)
      raise Error, "Response too large" if response.fetch(:body).bytesize > max_bytes
      if response[:status].to_i >= 500 && attempts < @retries
        attempts += 1
        redo_request = true
      else
        return response
      end
    rescue *NETWORK_ERRORS
      attempts += 1
      raise if attempts > @retries
      redo_request = true
    end while redo_request
  end

  def request(uri, ip:, max_bytes:)
    http = Net::HTTP.new(uri.host, uri.port, nil)
    http.ipaddr = ip
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10
    http.write_timeout = 5
    http.max_retries = 0
    result = nil
    http.start do
      http.request(Net::HTTP::Get.new(uri.request_uri, "User-Agent" => "StuttgartLiveRedirectInventory/1.0", "Accept-Encoding" => "identity")) do |response|
        raise Error, "Response too large" if response["content-length"].to_i > max_bytes
        body = +"".b
        response.read_body do |chunk|
          raise Error, "Response too large" if body.bytesize + chunk.bytesize > max_bytes
          body << chunk
        end
        result = { status: response.code.to_i, headers: response.each_header.to_h, body: body }
      end
    end
    result
  end
end
