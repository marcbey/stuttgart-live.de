require "net/http"
require "uri"

module Importing
  module LlmEnrichment
    class LinkValidator
      OPEN_TIMEOUT_SECONDS = 5
      READ_TIMEOUT_SECONDS = 10
      REDIRECT_LIMIT = 5
      USER_AGENT = "Mozilla/5.0 (compatible; StuttgartLiveBot/1.0; +https://stuttgart-live.de)".freeze
      ACCEPT_LANGUAGE = "de-DE,de;q=0.9,en;q=0.8".freeze
      UNAVAILABLE_PHRASES = [
        "Diese Seite ist leider nicht verfügbar",
        "Dieser Inhalt ist momentan nicht verfügbar"
      ].freeze
      LOGIN_WALL_PHRASES = [
        "Melde dich an",
        "Melde dich an, um fortzufahren",
        "Log in",
        "Log in to continue",
        "Sign in",
        "Sign in to continue",
        "Anmelden"
      ].freeze
      HOST_UNAVAILABLE_MARKERS = {
        "instagram.com" => [ "\"pageID\":\"httpErrorPage\"" ],
        "www.instagram.com" => [ "\"pageID\":\"httpErrorPage\"" ],
        "facebook.com" => [ "\"canonicalRouteName\":\"comet.fbweb.CometErrorRoute\"" ],
        "www.facebook.com" => [ "\"canonicalRouteName\":\"comet.fbweb.CometErrorRoute\"" ]
      }.freeze
      LOGIN_REDIRECT_HOSTS = {
        instagram_link: %w[instagram.com www.instagram.com],
        facebook_link: %w[facebook.com www.facebook.com]
      }.freeze

      Result = Data.define(
        :accepted,
        :sanitized_url,
        :status,
        :final_url,
        :http_status,
        :error_class,
        :matched_phrase,
        :checked_at
      ) do
        def accepted? = accepted

        def unverifiable? = status == "kept_unverifiable"

        def rejected? = status.start_with?("rejected_")

        def as_json(*)
          {
            status: status,
            final_url: final_url,
            http_status: http_status,
            error_class: error_class,
            matched_phrase: matched_phrase,
            checked_at: checked_at&.iso8601
          }.compact
        end
      end

      def initialize(fetcher: nil, clock: -> { Time.current })
        @fetcher = fetcher || method(:perform_get)
        @clock = clock
      end

      def call(url:, field_name:)
        value = url.to_s.strip
        raise ArgumentError, "url must be present" if value.blank?

        uri = parse_http_uri(value)
        return rejected_result(status: "rejected_invalid_url", original_url: value) if uri.blank?

        visited = []
        redirect_result = follow_redirects(uri, visited:, original_url: value)
        return redirect_result if redirect_result.is_a?(Result)

        response, final_uri = redirect_result
        response_body = normalize_response_body(response.body)

        host_unavailable_marker = detect_host_unavailable_marker(final_uri.host, response_body)
        if host_unavailable_marker.present?
          return rejected_result(
            status: "rejected_unavailable_text",
            original_url: value,
            final_url: final_uri,
            http_status: response.code.to_i,
            matched_phrase: host_unavailable_marker
          )
        end

        unavailable_phrase = detect_phrase(response_body, UNAVAILABLE_PHRASES)
        if unavailable_phrase.present?
          return rejected_result(
            status: "rejected_unavailable_text",
            original_url: value,
            final_url: final_uri,
            http_status: response.code.to_i,
            matched_phrase: unavailable_phrase
          )
        end

        login_wall_phrase = detect_phrase(response_body, LOGIN_WALL_PHRASES)
        if login_wall_phrase.present?
          if reject_login_redirect?(field_name, final_uri)
            return rejected_result(
              status: "rejected_login_redirect",
              original_url: value,
              final_url: final_uri,
              http_status: response.code.to_i,
              matched_phrase: login_wall_phrase
            )
          end

          return unverifiable_result(
            original_url: value,
            final_url: final_uri,
            http_status: response.code.to_i,
            matched_phrase: login_wall_phrase
          )
        end

        Result.new(
          accepted: true,
          sanitized_url: final_uri.to_s,
          status: "ok",
          final_url: final_uri.to_s,
          http_status: response.code.to_i,
          error_class: nil,
          matched_phrase: nil,
          checked_at: clock.call
        )
      rescue Timeout::Error => e
        unverifiable_result(original_url: value, error_class: e.class.to_s)
      rescue OpenSSL::SSL::SSLError => e
        rejected_result(status: "rejected_ssl_error", original_url: value, error_class: e.class.to_s)
      rescue SocketError, SystemCallError, IOError => e
        unverifiable_result(original_url: value, error_class: e.class.to_s)
      rescue URI::InvalidURIError => e
        rejected_result(status: "rejected_invalid_url", original_url: value, error_class: e.class.to_s)
      end

      private

      attr_reader :clock, :fetcher

      def parse_http_uri(value)
        uri = URI.parse(value)
        return unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return if uri.host.blank?

        uri
      rescue URI::InvalidURIError
        nil
      end

      def follow_redirects(uri, visited:, original_url:)
        current_uri = uri
        redirects = 0

        loop do
          return rejected_result(
            status: "rejected_redirect_loop",
            original_url: original_url,
            final_url: current_uri
          ) if visited.include?(current_uri.to_s)

          visited << current_uri.to_s
          response = fetcher.call(current_uri)
          code = response.code.to_i

          case code
          when 200..299
            return [ response, current_uri ]
          when 301, 302, 303, 307, 308
            location = response["location"].to_s.strip
            return unverifiable_result(
              original_url: original_url,
              final_url: current_uri,
              http_status: code
            ) if location.blank?

            redirects += 1
            return rejected_result(
              status: "rejected_redirect_limit",
              original_url: original_url,
              final_url: current_uri,
              http_status: code
            ) if redirects > REDIRECT_LIMIT

            current_uri = current_uri.merge(location)
          when 404, 410
            return rejected_result(
              status: "rejected_http_error",
              original_url: original_url,
              final_url: current_uri,
              http_status: code
            )
          when 500..599
            return rejected_result(
              status: "rejected_http_error",
              original_url: original_url,
              final_url: current_uri,
              http_status: code
            )
          when 403, 429
            return unverifiable_result(
              original_url: original_url,
              final_url: current_uri,
              http_status: code
            )
          else
            return unverifiable_result(
              original_url: original_url,
              final_url: current_uri,
              http_status: code
            )
          end
        end
      end

      def perform_get(uri)
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        request["Accept-Language"] = ACCEPT_LANGUAGE
        request["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT_SECONDS,
          read_timeout: READ_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end
      end

      def detect_phrase(body, phrases)
        phrases.find { |phrase| body.include?(phrase) }
      end

      def normalize_response_body(body)
        value = body.to_s
        return value if value.encoding == Encoding::UTF_8 && value.valid_encoding?

        value
          .dup
          .force_encoding(Encoding::UTF_8)
          .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
      end

      def detect_host_unavailable_marker(host, body)
        markers = HOST_UNAVAILABLE_MARKERS[host.to_s.downcase]
        return if markers.blank?

        detect_phrase(body, markers)
      end

      def reject_login_redirect?(field_name, final_uri)
        hosts = LOGIN_REDIRECT_HOSTS[field_name.to_sym]
        return false if hosts.blank?

        hosts.include?(final_uri.host.to_s.downcase) && final_uri.path.to_s.downcase.include?("login")
      end

      def rejected_result(status:, original_url: nil, final_url: nil, http_status: nil, error_class: nil, matched_phrase: nil)
        Result.new(
          accepted: false,
          sanitized_url: nil,
          status: status,
          final_url: final_url&.to_s,
          http_status: http_status,
          error_class: error_class,
          matched_phrase: matched_phrase,
          checked_at: clock.call
        )
      end

      def unverifiable_result(original_url: nil, final_url: nil, http_status: nil, error_class: nil, matched_phrase: nil)
        Result.new(
          accepted: true,
          sanitized_url: original_url || final_url&.to_s,
          status: "kept_unverifiable",
          final_url: final_url&.to_s,
          http_status: http_status,
          error_class: error_class,
          matched_phrase: matched_phrase,
          checked_at: clock.call
        )
      end
    end
  end
end
