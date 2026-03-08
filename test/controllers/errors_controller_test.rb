require "test_helper"

class ErrorsControllerTest < ActionDispatch::IntegrationTest
  test "renders generic 404 page for unknown routes" do
    get "/definitely-missing-page"

    assert_response :not_found
    assert_includes response.body, "Diese Seite gibt es nicht."
    assert_includes response.body, "Zur Startseite"
  end

  test "renders generic 500 preview page" do
    get "/errors/500"

    assert_response :internal_server_error
    assert_includes response.body, "Beim Laden ist etwas schiefgelaufen."
    assert_includes response.body, "Zur Startseite"
  end

  test "renders 404 page for unknown jpeg routes using html template" do
    get "/missing-image.jpeg"

    assert_response :not_found
    assert_includes response.body, "Diese Seite gibt es nicht."
    assert_equal "text/html; charset=utf-8", response.headers["Content-Type"]
  end
end
