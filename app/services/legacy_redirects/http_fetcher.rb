module LegacyRedirects
  class HttpFetcher < GuardedHttpFetcher
    private

    def validated_uri(url)
      uri = super
      raise Error, "URL is outside the legacy host allowlist" unless SourceKey::HOSTS.include?(uri.host&.downcase)

      uri
    end
  end
end
