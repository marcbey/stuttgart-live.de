require "test_helper"

class ErrorsControllerTest < ActionDispatch::IntegrationTest
  test "renders 404 with the public header and a full page return to the homepage" do
    get "/definitely-missing-page"

    assert_response :not_found
    assert_select "body.page-public.page-public-design-preview"
    assert_select ".design-preview-topbar a.design-preview-logo[href='#{root_path}']", count: 1
    assert_select ".design-preview-menu-button", count: 1
    assert_select ".design-preview-saved-link", count: 1
    assert_select "form[action='#{search_path}']", count: 2
    assert_select "h1", text: "Ups! Diese Seite gibt es leider nicht."
    assert_select ".public-error-actions a[href='#{root_path}'][data-turbo='false'][target='_top']", text: "Zur Startseite"
    assert_select "meta[name=robots][content='noindex, nofollow']"
    assert_select "meta[name=turbo-visit-control][content=reload]"
    assert_select "script[src*='public']", count: 1

    get root_path
    assert_response :success
  end

  test "404 recommendations only contain upcoming publicly available highlights" do
    events(:published_one).update_columns(highlighted: true)
    events(:published_past_one).update_columns(highlighted: true)
    events(:needs_review_two).update_columns(status: "published", published_at: Time.zone.local(2026, 5, 16))

    travel_to Time.zone.local(2026, 5, 15, 12) do
      get "/errors/404"

      assert_response :not_found
      assert_select "#not-found-highlights-title", text: "Unsere Highlights"
      assert_select ".design-preview-card .design-preview-card-title", text: "Published Artist", count: 1
      assert_select ".design-preview-card .design-preview-card-title", text: /Past Artist|Review Artist/, count: 0
    end
  end

  test "404 stays usable without available recommendations" do
    Event.update_all(status: "needs_review")

    get "/errors/404"

    assert_response :not_found
    assert_select ".design-preview-topbar", count: 1
    assert_select "#not-found-highlights-title", count: 0
    assert_select ".public-error-actions a[href='#{root_path}']", text: "Zur Startseite"
  end

  test "404 falls back to the independent error page when event loading fails" do
    original_method = Event.method(:published_live)
    Event.define_singleton_method(:published_live) { raise ActiveRecord::ConnectionNotEstablished, "Test database unavailable" }

    get "/errors/404"

    assert_response :not_found
    assert_select "body.public-error-page"
    assert_select "h1", text: "Ups! Diese Seite gibt es leider nicht."
    assert_select ".public-error-actions a[href='#{root_path}'][data-turbo='false'][target='_top']", text: "Zur Startseite"
    assert_select "script[src]", count: 0
  ensure
    Event.define_singleton_method(:published_live, original_method)
  end

  test "renders generic 500 preview page" do
    get "/errors/500"

    assert_response :internal_server_error
    assert_select "body.page-public"
    assert_select "h1", text: "Beim Laden ist etwas schiefgelaufen."
    assert_select ".app-error-status", text: /500/
    assert_select "a[href='#{news_index_path}']", text: "News"
    assert_select ".design-preview-card, script[src]", count: 0
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
    assert_select "main.public-error-main", count: 1
    assert_select ".app-error-status", text: /404/
    assert_equal "text/html; charset=utf-8", response.headers["Content-Type"]
  end

  test "422 page uses current design and offers newsletter recovery" do
    get "/errors/422"

    assert_response :unprocessable_entity
    assert_select "body.public-error-page"
    assert_select ".app-error-status", text: /422/
    assert_select "a[href=?]", new_newsletter_subscriber_path, text: "Zur Newsletter-Anmeldung"
    assert_select "meta[name=robots][content='noindex, nofollow']"
    assert_select "script[src]", count: 0
    assert_select "link[rel=stylesheet][href*='frontend']", count: 1
    assert_select "link[rel=stylesheet][href*='backend']", count: 0
  end
end
