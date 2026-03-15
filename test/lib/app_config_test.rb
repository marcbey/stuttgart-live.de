require "test_helper"

class AppConfigTest < ActiveSupport::TestCase
  test "production environment eagerly requires app config" do
    production_config = Rails.root.join("config/environments/production.rb").read

    assert_includes production_config, 'require Rails.root.join("app/lib/app_config").to_s'
  end

  test "prefers credentials over env values" do
    with_env("RESERVIX_API_KEY" => "env-api-key") do
      with_credentials(reservix: { api_key: "credentials-api-key" }) do
        assert_equal "credentials-api-key", AppConfig.reservix_api_key
      end
    end
  end

  test "falls back to env when credentials are missing" do
    with_env("MAILCHIMP_API_KEY" => "env-api-key") do
      with_credentials({}) do
        assert_equal "env-api-key", AppConfig.mailchimp_api_key
      end
    end
  end

  test "builds the eventim feed url from configured parts" do
    with_credentials(eventim: { user: "SRU", pass: "secret", feed_key: "35-sas8n7" }) do
      assert_equal "https://SRU:secret@pft.eventim.com/serve/35-sas8n7", AppConfig.eventim_feed_url
    end
  end

  private

  def with_credentials(values, &block)
    with_singleton_return_value(Rails.application, :credentials, values.deep_symbolize_keys, &block)
  end

  def with_env(values)
    original_values = {}

    values.each do |key, value|
      key = key.to_s
      original_values[key] = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    original_values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def with_singleton_return_value(target, method_name, value)
    original_method = target.method(method_name)

    target.singleton_class.send(:define_method, method_name) { value }
    yield
  ensure
    target.singleton_class.send(:define_method, method_name, original_method)
  end
end
