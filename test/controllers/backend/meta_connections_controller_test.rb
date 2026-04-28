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
    with_singleton_return_value(AppConfig, :meta_app_id, "123456") do
      with_singleton_return_value(AppConfig, :meta_instagram_app_id, "ignored-instagram-app") do
        with_singleton_return_value(AppConfig, :meta_app_secret, nil) do
          with_singleton_return_value(AppConfig, :meta_instagram_app_secret, nil) do
            get start_backend_meta_connection_url
          end
        end
      end
    end

    assert_redirected_to edit_backend_settings_url(section: "meta_connection")
    follow_redirect!
    assert_match "meta.app_secret ist nicht konfiguriert.", response.body
  end

  test "start uses configured instagram redirect uri override" do
    with_stubbed_meta_configuration_check do
      with_singleton_return_value(AppConfig, :meta_app_id, "123456") do
        with_singleton_return_value(AppConfig, :meta_app_secret, "secret") do
          with_singleton_return_value(AppConfig, :meta_instagram_redirect_uri, "http://www.example.com/backend/meta_connection/callback") do
            get start_backend_meta_connection_url
          end
        end
      end
    end

    assert_response :redirect
    assert_includes response.redirect_url, "https://www.facebook.com/v25.0/dialog/oauth?"
    assert_match(
      %r{redirect_uri=http%3A%2F%2Fwww\.example\.com%2Fbackend%2Fmeta_connection%2Fcallback},
      response.redirect_url
    )
  end

  test "start blocks with facebook specific message when configured redirect uri points to another host" do
    with_stubbed_meta_configuration_check do
      with_singleton_return_value(AppConfig, :meta_app_id, "123456") do
        with_singleton_return_value(AppConfig, :meta_app_secret, "secret") do
          with_singleton_return_value(AppConfig, :meta_instagram_redirect_uri, "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback") do
            get start_backend_meta_connection_url
          end
        end
      end
    end

    assert_redirected_to edit_backend_settings_url(section: "meta_connection")
    follow_redirect!
    assert_match "Facebook-Onboarding muss auf https://stuttgart-live.schopp3r.de gestartet werden", response.body
  end

  test "start instagram blocks with instagram specific message when configured redirect uri points to another host" do
    with_stubbed_meta_configuration_check do
      with_singleton_return_value(AppConfig, :meta_app_id, "123456") do
        with_singleton_return_value(AppConfig, :meta_app_secret, "secret") do
          with_singleton_return_value(AppConfig, :meta_instagram_redirect_uri, "https://stuttgart-live.schopp3r.de/backend/meta_connection/callback") do
            get start_instagram_backend_meta_connection_url
          end
        end
      end
    end

    assert_redirected_to edit_backend_settings_url(section: "meta_connection")
    follow_redirect!
    assert_match "Instagram-Onboarding muss auf https://stuttgart-live.schopp3r.de gestartet werden", response.body
  end

  test "disconnect instagram removes only instagram connection" do
    instagram_connection = create_social_connection!("instagram")
    facebook_connection = create_social_connection!("facebook")

    delete disconnect_instagram_backend_meta_connection_url

    assert_redirected_to edit_backend_settings_url(section: "meta_connection")
    assert_nil SocialConnection.find_by(id: instagram_connection.id)
    assert SocialConnection.exists?(facebook_connection.id)
  end

  test "disconnect facebook removes facebook connection and page targets" do
    facebook_connection = create_social_connection!("facebook")
    facebook_connection.social_connection_targets.create!(
      target_type: "facebook_page",
      external_id: "page-123",
      name: "Stuttgart Live",
      access_token: "page-token",
      selected: true,
      status: "selected"
    )

    delete disconnect_facebook_backend_meta_connection_url

    assert_redirected_to edit_backend_settings_url(section: "meta_connection")
    assert_nil SocialConnection.find_by(id: facebook_connection.id)
    assert_empty SocialConnectionTarget.where(social_connection_id: facebook_connection.id)
  end

  private

  def create_social_connection!(platform)
    SocialConnection.where(provider: "meta", platform:).destroy_all
    SocialConnection.create!(
      provider: "meta",
      platform:,
      auth_mode: platform == "facebook" ? "facebook_login_for_business" : "instagram_login",
      connection_status: "connected",
      user_access_token: "#{platform}-token",
      user_token_expires_at: 40.days.from_now,
      granted_scopes: []
    )
  end

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
