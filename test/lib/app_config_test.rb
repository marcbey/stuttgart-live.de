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

  test "reads meta values from credentials" do
    with_credentials(meta: {
      app_id: "meta-app-id",
      app_secret: "meta-app-secret",
      instagram_app_id: "instagram-app-id",
      instagram_app_secret: "instagram-app-secret",
      instagram_redirect_uri: "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback",
      facebook_page_id: "page-123",
      facebook_page_access_token: "page-token",
      instagram_business_account_id: "ig-123"
    }) do
      assert_equal "meta-app-id", AppConfig.meta_app_id
      assert_equal "meta-app-secret", AppConfig.meta_app_secret
      assert_equal "instagram-app-id", AppConfig.meta_instagram_app_id
      assert_equal "instagram-app-secret", AppConfig.meta_instagram_app_secret
      assert_equal "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback", AppConfig.meta_instagram_redirect_uri
      assert_equal "page-123", AppConfig.meta_facebook_page_id
      assert_equal "page-token", AppConfig.meta_facebook_page_access_token
      assert_equal "ig-123", AppConfig.meta_instagram_business_account_id
    end
  end

  test "falls back to env for meta values" do
    with_env(
      "META_APP_ID" => "env-app-id",
      "META_INSTAGRAM_APP_ID" => "env-instagram-app-id",
      "META_INSTAGRAM_APP_SECRET" => "env-instagram-app-secret",
      "META_INSTAGRAM_REDIRECT_URI" => "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback",
      "META_FACEBOOK_PAGE_ID" => "env-page-id",
      "META_FACEBOOK_PAGE_ACCESS_TOKEN" => "env-page-token",
      "META_INSTAGRAM_BUSINESS_ACCOUNT_ID" => "env-ig-id"
    ) do
      with_credentials({}) do
        assert_equal "env-app-id", AppConfig.meta_app_id
        assert_equal "env-instagram-app-id", AppConfig.meta_instagram_app_id
        assert_equal "env-instagram-app-secret", AppConfig.meta_instagram_app_secret
        assert_equal "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback", AppConfig.meta_instagram_redirect_uri
        assert_equal "env-page-id", AppConfig.meta_facebook_page_id
        assert_equal "env-page-token", AppConfig.meta_facebook_page_access_token
        assert_equal "env-ig-id", AppConfig.meta_instagram_business_account_id
      end
    end
  end

  test "falls back from instagram login keys to legacy meta app keys" do
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
