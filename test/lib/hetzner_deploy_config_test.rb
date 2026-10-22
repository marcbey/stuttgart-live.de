require "test_helper"
require "tempfile"
require "support/deploy_config_helper"

class HetznerDeployConfigTest < ActiveSupport::TestCase
  include DeployConfigHelper

  test "production log retention applies to both roles with canonical routing and the selected web profile" do
    raw = render_deploy_config(destination: "hetzner", env: { "PRODUCTION_DOMAIN_MODE" => "live" })
    config = Kamal::Configuration.new(raw.symbolize_keys, destination: "hetzner")
    config.roles.each do |role|
      assert_includes role.logging_args, 'max-size="10m"'
      assert_includes role.logging_args, 'max-file="3"'
    end
    assert_equal 3, raw.dig("servers", "web", "env", "clear", "WEB_CONCURRENCY")
    assert_equal 2, raw.dig("servers", "web", "env", "clear", "RAILS_MAX_THREADS")
    assert_equal 3, raw.dig("servers", "web", "env", "clear", "DB_POOL")
    assert_equal "false", raw.dig("env", "clear", "STAGING_NOINDEX")
    assert_includes raw.dig("proxy", "hosts"), "stuttgart-live.de"
  end

  test "reads values from the shared deploy config" do
    with_deploy_config(
      "app_host" => "example.com",
      "web_host" => "203.0.113.10",
      "ssh_host_key" => "203.0.113.10 ssh-ed25519 AAAATEST"
    ) do
      assert_equal "example.com", HetznerDeployConfig.app_host
      assert_equal "203.0.113.10", HetznerDeployConfig.web_host
      assert_equal "203.0.113.10 ssh-ed25519 AAAATEST", HetznerDeployConfig.ssh_host_key
    end
  end

  test "returns nil for optional app host when deploy config is missing" do
    with_missing_deploy_config do
      assert_nil HetznerDeployConfig.app_host_if_present
    end
  end

  test "raises a helpful error for required values when deploy config is missing" do
    error = with_missing_deploy_config do
      assert_raises(HetznerDeployConfig::MissingConfigError) do
        HetznerDeployConfig.app_host
      end
    end

    assert_includes error.message, "Missing Hetzner deploy config"
  end

  private

  def with_deploy_config(values)
    Tempfile.create([ "deploy-hetzner", ".yml" ]) do |file|
      file.write(values.to_yaml)
      file.flush

      with_config_path(file.path) { yield }
    end
  end

  def with_missing_deploy_config
    with_config_path("/tmp/stuttgart-live-missing-deploy-config.yml") { yield }
  end

  def with_config_path(path)
    original_defined = HetznerDeployConfig.instance_variable_defined?(:@config)
    original_value = HetznerDeployConfig.instance_variable_get(:@config)

    HetznerDeployConfig.remove_instance_variable(:@config) if original_defined
    with_singleton_return_value(HetznerDeployConfig, :config_path, path) { yield }
  ensure
    HetznerDeployConfig.remove_instance_variable(:@config) if HetznerDeployConfig.instance_variable_defined?(:@config)
    HetznerDeployConfig.instance_variable_set(:@config, original_value) if original_defined
  end

  def with_singleton_return_value(target, method_name, value)
    original_method = target.method(method_name)

    target.singleton_class.send(:define_method, method_name) { value }
    yield
  ensure
    target.singleton_class.send(:define_method, method_name, original_method)
  end
end
