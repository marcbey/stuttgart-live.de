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
end
