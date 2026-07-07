module ProductionServerConfig
  module_function

  def media_proxy_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("MEDIA_PROXY_ENABLED", "false"))
  end

  def media_proxy_secret
    ENV["MEDIA_PROXY_SECRET"].to_s.strip
  end
end
