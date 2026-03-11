# frozen_string_literal: true

require "kamal"
require "kamal/commands/registry"
require "kamal/utils"

class Kamal::Commands::Registry
  unless method_defined?(:login_without_optional_skip)
    alias_method :login_without_optional_skip, :login
  end

  def login(registry_config: nil)
    return if ENV["KAMAL_SKIP_REMOTE_REGISTRY_LOGIN"] == "true"

    registry_config ||= config.registry

    return if registry_config.local?

    # Kamal 2.10.1 nutzt hier noch `docker login -p ...`, was mit GHCR
    # in unserem Setup unzuverlässig war. `--password-stdin` funktioniert
    # sowohl lokal als auch in GitHub Actions stabiler.
    pipe \
      [ :printf, "%s", sensitive(Kamal::Utils.escape_shell_value(registry_config.password)) ],
      docker(
        :login,
        registry_config.server,
        "-u", sensitive(Kamal::Utils.escape_shell_value(registry_config.username)),
        "--password-stdin"
      )
  end
end
