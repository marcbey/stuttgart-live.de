require "test_helper"

module Importing
  module LlmEnrichment
    class LinkValidatorTest < ActiveSupport::TestCase
      FakeResponse = Struct.new(:code, :body, :headers, keyword_init: true) do
        def [](key)
          headers.fetch(key.to_s.downcase, nil)
        end
      end

      test "keeps a successful reachable link" do
        validator = build_validator(
          "https://example.com/page" => FakeResponse.new(code: "200", body: "<html>ok</html>", headers: {})
        )

        result = validator.call(url: "https://example.com/page", field_name: :homepage_link)

        assert_equal true, result.accepted?
        assert_equal "ok", result.status
        assert_equal "https://example.com/page", result.sanitized_url
        assert_equal 200, result.http_status
      end

      test "rejects 404 links" do
        validator = build_validator(
          "https://example.com/missing" => FakeResponse.new(code: "404", body: "", headers: {})
        )

        result = validator.call(url: "https://example.com/missing", field_name: :homepage_link)

        assert_equal false, result.accepted?
        assert_equal "rejected_http_error", result.status
        assert_nil result.sanitized_url
      end

      test "rejects 500 links" do
        validator = build_validator(
          "https://example.com/error" => FakeResponse.new(code: "500", body: "", headers: {})
        )

        result = validator.call(url: "https://example.com/error", field_name: :homepage_link)

        assert_equal false, result.accepted?
        assert_equal "rejected_http_error", result.status
      end

      test "rejects unavailable page phrase" do
        validator = build_validator(
          "https://facebook.com/unavailable" => FakeResponse.new(
            code: "200",
            body: "<html>Diese Seite ist leider nicht verfügbar</html>",
            headers: {}
          )
        )

        result = validator.call(url: "https://facebook.com/unavailable", field_name: :facebook_link)

        assert_equal false, result.accepted?
        assert_equal "rejected_unavailable_text", result.status
        assert_equal "Diese Seite ist leider nicht verfügbar", result.matched_phrase
      end

      test "rejects second unavailable page phrase" do
        validator = build_validator(
          "https://facebook.com/content" => FakeResponse.new(
            code: "200",
            body: "<html>Dieser Inhalt ist momentan nicht verfügbar</html>",
            headers: {}
          )
        )

        result = validator.call(url: "https://facebook.com/content", field_name: :facebook_link)

        assert_equal false, result.accepted?
        assert_equal "rejected_unavailable_text", result.status
        assert_equal "Dieser Inhalt ist momentan nicht verfügbar", result.matched_phrase
      end

      test "rejects instagram pages flagged as http error pages" do
        validator = build_validator(
          "https://www.instagram.com/lucanoel.music/" => FakeResponse.new(
            code: "200",
            body: "<html><script>{\"pageID\":\"httpErrorPage\"}</script></html>",
            headers: {}
          )
        )

        result = validator.call(url: "https://www.instagram.com/lucanoel.music/", field_name: :instagram_link)

        assert_equal false, result.accepted?
        assert_equal "rejected_unavailable_text", result.status
        assert_equal "\"pageID\":\"httpErrorPage\"", result.matched_phrase
      end

      test "rejects facebook pages flagged as comet error routes" do
        validator = build_validator(
          "https://www.facebook.com/theaterrampe/" => FakeResponse.new(
            code: "200",
            body: "<html><script>{\"canonicalRouteName\":\"comet.fbweb.CometErrorRoute\"}</script></html>",
            headers: {}
          )
        )

        result = validator.call(url: "https://www.facebook.com/theaterrampe/", field_name: :facebook_link)

        assert_equal false, result.accepted?
        assert_equal "rejected_unavailable_text", result.status
        assert_equal "\"canonicalRouteName\":\"comet.fbweb.CometErrorRoute\"", result.matched_phrase
      end

      test "normalizes binary response bodies before checking unavailable markers" do
        body = "<html>\xC3<script>{\"pageID\":\"httpErrorPage\"}</script></html>".b
        validator = build_validator(
          "https://www.instagram.com/lucanoelmusic/" => FakeResponse.new(
            code: "200",
            body: body,
            headers: {}
          )
        )

        result = validator.call(url: "https://www.instagram.com/lucanoelmusic/", field_name: :instagram_link)

        assert_equal false, result.accepted?
        assert_equal "rejected_unavailable_text", result.status
        assert_equal "\"pageID\":\"httpErrorPage\"", result.matched_phrase
      end

      test "follows redirects to a valid destination" do
        validator = build_validator(
          "https://example.com/start" => FakeResponse.new(
            code: "302",
            body: "",
            headers: { "location" => "https://example.com/final" }
          ),
          "https://example.com/final" => FakeResponse.new(code: "200", body: "<html>ok</html>", headers: {})
        )

        result = validator.call(url: "https://example.com/start", field_name: :homepage_link)

        assert_equal true, result.accepted?
        assert_equal "https://example.com/final", result.sanitized_url
        assert_equal "https://example.com/final", result.final_url
      end

      test "rejects redirect target with hard failure" do
        validator = build_validator(
          "https://example.com/start" => FakeResponse.new(
            code: "302",
            body: "",
            headers: { "location" => "https://example.com/missing" }
          ),
          "https://example.com/missing" => FakeResponse.new(code: "404", body: "", headers: {})
        )

        result = validator.call(url: "https://example.com/start", field_name: :homepage_link)

        assert_equal false, result.accepted?
        assert_equal "rejected_http_error", result.status
      end

      test "keeps 403 links as unverifiable" do
        validator = build_validator(
          "https://instagram.com/private" => FakeResponse.new(code: "403", body: "", headers: {})
        )

        result = validator.call(url: "https://instagram.com/private", field_name: :instagram_link)

        assert_equal true, result.accepted?
        assert_equal "kept_unverifiable", result.status
        assert_equal "https://instagram.com/private", result.sanitized_url
      end

      test "keeps 429 links as unverifiable" do
        validator = build_validator(
          "https://youtube.com/channel/test" => FakeResponse.new(code: "429", body: "", headers: {})
        )

        result = validator.call(url: "https://youtube.com/channel/test", field_name: :youtube_link)

        assert_equal true, result.accepted?
        assert_equal "kept_unverifiable", result.status
      end

      test "keeps timeout as unverifiable" do
        validator = LinkValidator.new(fetcher: ->(_uri) { raise Timeout::Error, "timed out" })

        result = validator.call(url: "https://example.com/slow", field_name: :homepage_link)

        assert_equal true, result.accepted?
        assert_equal "kept_unverifiable", result.status
        assert_equal "Timeout::Error", result.error_class
      end

      test "rejects ssl certificate errors" do
        validator = LinkValidator.new(fetcher: ->(_uri) { raise OpenSSL::SSL::SSLError, "certificate verify failed" })

        result = validator.call(url: "https://example.com/ssl-problem", field_name: :homepage_link)

        assert_equal false, result.accepted?
        assert_equal "rejected_ssl_error", result.status
        assert_equal "OpenSSL::SSL::SSLError", result.error_class
      end

      test "rejects invalid or non-http URLs" do
        validator = build_validator

        result = validator.call(url: "mailto:test@example.com", field_name: :homepage_link)

        assert_equal false, result.accepted?
        assert_equal "rejected_invalid_url", result.status
      end

      private

      def build_validator(responses = {})
        LinkValidator.new(
          fetcher: lambda do |uri|
            responses.fetch(uri.to_s) do
              raise "missing fake response for #{uri}"
            end
          end
        )
      end
    end
  end
end
