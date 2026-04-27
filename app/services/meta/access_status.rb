require "digest"

module Meta
  class AccessStatus
    Status = Data.define(
      :connection_status,
      :state,
      :summary,
      :details,
      :checked_at,
      :expires_at,
      :page_name,
      :instagram_username,
      :permissions,
      :debug_available,
      :reauth_required,
      :payload
    ) do
      def ok?
        state == :ok
      end

      def warning?
        state == :warning
      end

      def error?
        state == :error
      end

      def can_publish?
        ok? || warning?
      end
    end

    CACHE_NAMESPACE = "meta/access-status".freeze
    CACHE_TTL = 10.minutes

    def initialize(cache: Rails.cache, health_check: ConnectionHealthCheck.new, connection_resolver: ConnectionResolver.new, platform: nil)
      @cache = cache
      @health_check = health_check
      @connection_resolver = connection_resolver
      @platform = platform.to_s.strip.presence
    end

    def call(force: false, platform: nil)
      active_platform = platform.presence || self.platform
      return fetch_status(platform: active_platform) unless force

      cache.delete(cache_key(platform: active_platform))
      fetch_status(platform: active_platform)
    end

    def ensure_publishable!(force: false, platform: nil)
      status = call(force:, platform: platform.presence || self.platform)
      return status if status.can_publish?

      raise Error, status.summary
    end

    private

    attr_reader :cache, :connection_resolver, :health_check, :platform

    def fetch_status(platform:)
      cache.fetch(cache_key(platform:), expires_in: CACHE_TTL) { build_status(platform:) }
    end

    def build_status(platform:)
      connection = platform.present? ? connection_resolver.connection_for(platform) : connection_resolver.connection
      health_check.call(connection:, refresh: true, platform:)
    end

    def cache_key(platform:)
      connection = platform.present? ? connection_resolver.connection_for(platform) : connection_resolver.connection
      return "#{CACHE_NAMESPACE}/#{platform || 'default'}/missing" if connection.blank?

      token_digest = Digest::SHA256.hexdigest(connection.user_access_token.to_s)
      [ CACHE_NAMESPACE, platform || connection.platform, connection.id, connection.updated_at.to_i, token_digest ].join("/")
    end
  end
end
