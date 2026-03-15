require "yaml"

module HetznerDeployConfig
  CONFIG_PATH = File.expand_path("../../config/deploy.hetzner.shared.yml", __dir__)

  class << self
    def app_host
      fetch("app_host")
    end

    def web_host
      fetch("web_host")
    end

    def ssh_host_key
      fetch("ssh_host_key")
    end

    def fetch(key)
      config.fetch(key)
    end

    private

    def config
      @config ||= YAML.safe_load(File.read(CONFIG_PATH))
    end
  end
end
