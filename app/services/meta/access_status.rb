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

    def initialize(cache: Rails.cache, health_check: ConnectionHealthCheck.new, connection_resolver: ConnectionResolver.new)
      @cache = cache
      @health_check = health_check
      @connection_resolver = connection_resolver
    end

    def call(force: false)
      return fetch_status unless force

      cache.delete(cache_key)
      fetch_status
    end

    def ensure_publishable!(force: false)
      status = call(force:)
      return status if status.can_publish?

      raise Error, status.summary
    end

    private

    attr_reader :cache, :connection_resolver, :health_check

    def fetch_status
      cache.fetch(cache_key, expires_in: CACHE_TTL) { build_status }
    end

    def build_status
      health_check.call(connection: connection_resolver.connection, refresh: true)
    end

    def cache_key
      connection = connection_resolver.connection
      return "#{CACHE_NAMESPACE}/missing" if connection.blank?

      token_digest = Digest::SHA256.hexdigest(connection.user_access_token.to_s)
      [ CACHE_NAMESPACE, connection.id, connection.updated_at.to_i, token_digest ].join("/")
    end
  end
end
