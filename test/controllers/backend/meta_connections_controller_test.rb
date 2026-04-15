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
      with_singleton_return_value(AppConfig, :meta_app_secret, nil) do
        get start_backend_meta_connection_url
      end
    end

    assert_redirected_to edit_backend_settings_url(section: "meta_connection")
    follow_redirect!
    assert_match "meta.app_secret ist nicht konfiguriert.", response.body
  end

  private

  def with_singleton_return_value(target, method_name, value)
    original_method = target.method(method_name)

    target.define_singleton_method(method_name) { value }
    yield
  ensure
    target.define_singleton_method(method_name, original_method)
  end
end
