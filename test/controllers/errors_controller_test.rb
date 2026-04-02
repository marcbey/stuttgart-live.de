require "test_helper"

class ErrorsControllerTest < ActionDispatch::IntegrationTest
  test "renders generic 404 page for unknown routes" do
    get "/definitely-missing-page"

    assert_response :not_found
    assert_select "body.page-public"
    assert_select ".app-nav .brand-wordmark-poster", count: 1
    assert_select "section.info-page-shell.app-error-page", count: 1
    assert_select ".info-page-card", minimum: 3
    assert_select "h1", text: "Diese Seite gibt es nicht."
    assert_select "a.button[href='#{root_path}']", text: "Zur Startseite"
  end

  test "renders generic 500 preview page" do
    get "/errors/500"

    assert_response :internal_server_error
    assert_select "body.page-public"
    assert_select "h1", text: "Beim Laden ist etwas schiefgelaufen."
    assert_select ".app-error-status", text: /500/
    assert_select "a[href='#{news_index_path}']", text: "News"
  end

  test "renders 400 page with back action when referer is present" do
    get "/errors/400", headers: { "HTTP_REFERER" => root_url }

    assert_response :bad_request
    assert_select "h1", text: "Diese Anfrage passt nicht."
    assert_select "a.button-secondary[href='#{root_url}']", text: "Zurück"
  end

  test "renders 404 page for unknown jpeg routes using html template" do
    get "/missing-image.jpeg"

    assert_response :not_found
    assert_select "section.info-page-shell.app-error-page", count: 1
    assert_select ".app-error-status", text: /404/
    assert_equal "text/html; charset=utf-8", response.headers["Content-Type"]
  end
end
