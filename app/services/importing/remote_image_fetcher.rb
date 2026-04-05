require "marcel"
require "net/http"
require "stringio"
require "uri"

module Importing
  class RemoteImageFetcher
    DownloadedFile = Data.define(:io, :filename, :content_type)
    FetchError = Class.new(StandardError)

    MAX_REDIRECTS = 3
    MAX_DOWNLOAD_BYTES = 10.megabytes
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5
    USER_AGENT = "StuttgartLiveImageCache/1.0".freeze

    def self.call(url:)
      new(url:).call
    end

    def initialize(url:)
      @url = url.to_s
    end

    def call
      uri = URI.parse(url)
      raise FetchError, "Bild-URL muss mit http:// oder https:// beginnen." unless uri.is_a?(URI::HTTP)

      fetch(uri:, redirects_remaining: MAX_REDIRECTS)
    rescue URI::InvalidURIError => error
      raise FetchError, "Ungültige Bild-URL: #{error.message}"
    end

    private

    attr_reader :url

    def fetch(uri:, redirects_remaining:)
      response = perform_request(uri)

      case response
      when Net::HTTPSuccess
        build_downloaded_file(response:, uri:)
      when Net::HTTPRedirection
        location = response["location"].to_s.strip
        raise FetchError, "Bildweiterleitung ohne Ziel-URL." if location.blank?
        raise FetchError, "Zu viele Weiterleitungen beim Laden des Bildes." if redirects_remaining <= 0

        fetch(uri: URI.join(uri.to_s, location), redirects_remaining: redirects_remaining - 1)
      else
        raise FetchError, "Bild konnte nicht geladen werden (HTTP #{response.code})."
      end
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError, SocketError => error
      raise FetchError, "Bild konnte nicht geladen werden: #{error.message}"
    end

    def perform_request(uri)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        http.request(request)
      end
    end

    def build_downloaded_file(response:, uri:)
      validate_declared_size!(response)

      body = read_body(response)
      raise FetchError, "Bildantwort ist leer." if body.blank?

      content_type = detected_content_type(response:, body:, uri:)
      raise FetchError, "Antwort ist kein Bild." unless content_type.start_with?("image/")

      DownloadedFile.new(
        io: StringIO.new(body),
        filename: filename_for(uri),
        content_type:
      )
    end

    def validate_declared_size!(response)
      declared_size = response["content-length"].to_i
      return if declared_size <= 0
      return if declared_size <= MAX_DOWNLOAD_BYTES

      raise FetchError, "Bild ist größer als #{ActiveSupport::NumberHelper.number_to_human_size(MAX_DOWNLOAD_BYTES)}."
    end

    def read_body(response)
      return validate_body_size!(response.body.to_s.b) unless response.respond_to?(:read_body)

      body = +""
      response.read_body do |chunk|
        body << chunk
        validate_body_size!(body)
      end
      body
    end

    def validate_body_size!(body)
      return body if body.bytesize <= MAX_DOWNLOAD_BYTES

      raise FetchError, "Bild ist größer als #{ActiveSupport::NumberHelper.number_to_human_size(MAX_DOWNLOAD_BYTES)}."
    end

    def detected_content_type(response:, body:, uri:)
      response.content_type.to_s.presence ||
        Marcel::MimeType.for(StringIO.new(body), name: filename_for(uri), declared_type: response["content-type"])
    end

    def filename_for(uri)
      basename = File.basename(uri.path.to_s)
      return basename if basename.present? && basename != "/"

      "import-image"
    end
  end
end
