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

  test "reads mailjet config from credentials" do
    with_env(
      "MAILJET_API_KEY" => "env-api-key",
      "MAILJET_SECRET_KEY" => "env-secret-key",
      "MAILJET_LIST_ID" => "env-list-id",
      "MAILJET_API_ENDPOINT" => "https://api.us.mailjet.com"
    ) do
      with_credentials(mailjet: {
        api_key: "credentials-api-key",
        secret_key: "credentials-secret-key",
        list_id: "credentials-list-id",
        api_endpoint: "https://api.mailjet.com"
      }) do
        assert_equal "credentials-api-key", AppConfig.mailjet_api_key
        assert_equal "credentials-secret-key", AppConfig.mailjet_secret_key
        assert_equal "credentials-list-id", AppConfig.mailjet_list_id
        assert_equal "https://api.mailjet.com", AppConfig.mailjet_api_endpoint
      end
    end
  end

  test "falls back to mailjet env values when credentials are missing" do
    with_env(
      "MAILJET_API_KEY" => "env-api-key",
      "MAILJET_SECRET_KEY" => "env-secret-key",
      "MAILJET_LIST_ID" => "env-list-id",
      "MAILJET_API_ENDPOINT" => "https://api.us.mailjet.com"
    ) do
      with_credentials({}) do
        assert_equal "env-api-key", AppConfig.mailjet_api_key
        assert_equal "env-secret-key", AppConfig.mailjet_secret_key
        assert_equal "env-list-id", AppConfig.mailjet_list_id
        assert_equal "https://api.us.mailjet.com", AppConfig.mailjet_api_endpoint
      end
    end
  end

  test "falls back to mailjet default env key names" do
    with_env(
      "MAILJET_API_KEY" => nil,
      "MAILJET_SECRET_KEY" => nil,
      "MJ_APIKEY_PUBLIC" => "mj-public-key",
      "MJ_APIKEY_PRIVATE" => "mj-private-key"
    ) do
      with_credentials({}) do
        assert_equal "mj-public-key", AppConfig.mailjet_api_key
        assert_equal "mj-private-key", AppConfig.mailjet_secret_key
      end
    end
  end

  test "reads openwebninja api key from credentials" do
    with_credentials(openwebninja: { api_key: "openweb-secret" }) do
      assert_equal "openweb-secret", AppConfig.openwebninja_api_key
    end
  end

  test "falls back to env for openwebninja api key" do
    with_env("OPENWEBNINJA_API_KEY" => "env-openweb-secret") do
      with_credentials({}) do
        assert_equal "env-openweb-secret", AppConfig.openwebninja_api_key
      end
    end
  end

  test "builds the eventim feed url from configured parts" do
    with_credentials(eventim: { user: "SRU", pass: "secret", feed_key: "35-sas8n7" }) do
      assert_equal "https://SRU:secret@pft.eventim.com/serve/35-sas8n7", AppConfig.eventim_feed_url
    end
  end

  test "reads mailer from address from credentials" do
    with_credentials(mailer: { from: "Stuttgart Live <mail@example.com>" }) do
      assert_equal "Stuttgart Live <mail@example.com>", AppConfig.mailer_from
    end
  end

  test "falls back to env for mailer from address" do
    with_env("MAILER_FROM" => "Stuttgart Live <env-mail@example.com>") do
      with_credentials({}) do
        assert_equal "Stuttgart Live <env-mail@example.com>", AppConfig.mailer_from
      end
    end
  end

  test "reads meta values from credentials" do
    with_credentials(meta: {
      app_id: "meta-app-id",
      app_secret: "meta-app-secret",
      instagram_app_id: "instagram-app-id",
      instagram_app_secret: "instagram-app-secret",
      instagram_redirect_uri: "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback"
    }) do
      assert_equal "meta-app-id", AppConfig.meta_app_id
      assert_equal "meta-app-secret", AppConfig.meta_app_secret
      assert_equal "instagram-app-id", AppConfig.meta_instagram_app_id
      assert_equal "instagram-app-secret", AppConfig.meta_instagram_app_secret
      assert_equal "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback", AppConfig.meta_instagram_redirect_uri
    end
  end

  test "falls back to env for meta values" do
    with_env(
      "META_APP_ID" => "env-app-id",
      "META_APP_SECRET" => "env-app-secret",
      "META_INSTAGRAM_APP_ID" => "env-instagram-app-id",
      "META_INSTAGRAM_APP_SECRET" => "env-instagram-app-secret",
      "META_INSTAGRAM_REDIRECT_URI" => "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback"
    ) do
      with_credentials({}) do
        assert_equal "env-app-id", AppConfig.meta_app_id
        assert_equal "env-instagram-app-id", AppConfig.meta_instagram_app_id
        assert_equal "env-instagram-app-secret", AppConfig.meta_instagram_app_secret
        assert_equal "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback", AppConfig.meta_instagram_redirect_uri
      end
    end
  end

  test "falls back from instagram login keys to meta app keys" do
    with_credentials(meta: { app_id: "legacy-app-id", app_secret: "legacy-app-secret" }) do
      assert_equal "legacy-app-id", AppConfig.meta_instagram_app_id
      assert_equal "legacy-app-secret", AppConfig.meta_instagram_app_secret
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
