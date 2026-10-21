module Backend
  module Events
    class ReturnPath
      def self.resolve(value, base_url:)
        return if value.blank?

        decoded = URI::DEFAULT_PARSER.unescape(value.to_s)
        return if decoded.match?(/[\\\x00-\x1f\x7f]/) || decoded.start_with?("//")

        uri = URI.parse(value.to_s)
        base = URI.parse(base_url)
        if uri.host.present?
          return unless uri.scheme == base.scheme && uri.host == base.host && uri.port == base.port
        else
          return if uri.scheme.present? || !uri.path.start_with?("/")
        end
        return if uri.userinfo.present?

        path = uri.path
        path += "?#{uri.query}" if uri.query.present?
        path += "##{uri.fragment}" if uri.fragment.present?
        path
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
