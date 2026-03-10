# frozen_string_literal: true

require "kamal"
require "kamal/commands/registry"

class Kamal::Commands::Registry
  unless method_defined?(:login_without_optional_skip)
    alias_method :login_without_optional_skip, :login
  end

  def login(registry_config: nil)
    return if ENV["KAMAL_SKIP_REMOTE_REGISTRY_LOGIN"] == "true"

    login_without_optional_skip(registry_config: registry_config)
  end
end
