module ProductionServerConfig
  module_function

  def media_proxy_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("MEDIA_PROXY_ENABLED", "false"))
  end

  def media_proxy_secret
    ENV["MEDIA_PROXY_SECRET"].to_s.strip
  end

  def media_proxy_ttl
    ENV.fetch("MEDIA_PROXY_TTL", 1.year.to_i).to_i
  end
end
