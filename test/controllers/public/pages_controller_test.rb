require "test_helper"

class Public::PagesControllerTest < ActionDispatch::IntegrationTest
  test "contact page is publicly accessible" do
    get contact_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Kontakt"
    assert_includes response.body, "Bestell-Hotline"
    assert_includes response.body, "arnulfwoock@russ-live.de"
  end

  test "imprint page is publicly accessible" do
    get imprint_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Impressum"
    assert_includes response.body, "SKS Erwin Russ GmbH"
    assert_includes response.body, "DE 147867476"
  end

  test "footer pages are publicly accessible" do
    get datenschutz_url

    assert_response :success
    assert_includes response.body, "Datenschutz"
    assert_includes response.body, "stuttgart-live.de/datenschutz"

    get imprint_url

    assert_response :success
    assert_includes response.body, "Impressum"
    assert_includes response.body, "Charlottenplatz 17"

    get agb_url

    assert_response :success
    assert_includes response.body, "AGB"
    assert_includes response.body, "Easy Ticket"

    get contact_url

    assert_response :success
    assert_includes response.body, "Kontakt"
    assert_includes response.body, "0711"
  end

  test "footer navigation is rendered on public pages" do
    get events_url

    assert_response :success
    assert_select ".site-footer-nav a", text: "Datenschutz"
    assert_select ".site-footer-nav a", text: "Impressum"
    assert_select ".site-footer-nav a", text: "AGB"
    assert_select ".site-footer-nav a", text: "Kontakt"
  end
end
