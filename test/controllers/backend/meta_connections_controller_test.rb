require "test_helper"

class Backend::MetaConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)
    sign_in_as(@admin)
  end

  teardown do
    sign_out
  end

  test "start redirects back with clear error when meta app secret is missing" do
    with_singleton_return_value(AppConfig, :meta_instagram_app_id, "123456") do
      with_singleton_return_value(AppConfig, :meta_instagram_app_secret, nil) do
        get start_backend_meta_connection_url
      end
    end

    assert_redirected_to edit_backend_settings_url(section: "meta_connection")
    follow_redirect!
    assert_match "meta.instagram_app_secret ist nicht konfiguriert.", response.body
  end

  test "start uses configured instagram redirect uri override" do
    with_stubbed_meta_configuration_check do
      with_singleton_return_value(AppConfig, :meta_instagram_app_id, "123456") do
        with_singleton_return_value(AppConfig, :meta_instagram_app_secret, "secret") do
          with_singleton_return_value(AppConfig, :meta_instagram_redirect_uri, "http://www.example.com/backend/meta_connection/callback") do
            get start_backend_meta_connection_url
          end
        end
      end
    end

    assert_response :redirect
    assert_includes response.redirect_url, "https://www.instagram.com/oauth/authorize?"
    assert_match(
      %r{redirect_uri=http%3A%2F%2Fwww\.example\.com%2Fbackend%2Fmeta_connection%2Fcallback},
      response.redirect_url
    )
  end

  test "start blocks when configured instagram redirect uri points to another host" do
    with_stubbed_meta_configuration_check do
      with_singleton_return_value(AppConfig, :meta_instagram_app_id, "123456") do
        with_singleton_return_value(AppConfig, :meta_instagram_app_secret, "secret") do
          with_singleton_return_value(AppConfig, :meta_instagram_redirect_uri, "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback") do
            get start_backend_meta_connection_url
          end
        end
      end
    end

    assert_redirected_to edit_backend_settings_url(section: "meta_connection")
    follow_redirect!
    assert_match "Instagram-Onboarding muss auf https://stuttgart-live.schopp3r.de gestartet werden", response.body
  end

  private

  def with_stubbed_meta_configuration_check
    configuration = Object.new
    configuration.define_singleton_method(:ensure_configured!) { true }

    with_singleton_return_value(Meta::Onboarding::Configuration, :new, configuration) do
      yield
    end
  end

  def with_singleton_return_value(target, method_name, value)
    original_method = target.method(method_name)

    target.define_singleton_method(method_name) { value }
    yield
  ensure
    target.define_singleton_method(method_name, original_method)
  end
end
