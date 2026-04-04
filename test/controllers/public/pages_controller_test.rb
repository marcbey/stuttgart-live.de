require "test_helper"

class Public::PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    StaticPageDefaults.ensure!
  end

  test "contact page is publicly accessible" do
    get contact_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Kontakt"
    assert_includes response.body, "Bestell-Hotline"
    assert_includes response.body, "arnulfwoock@russ-live.de"
    assert_select ".info-page-card", count: 4
    assert_select ".info-page-card.info-page-card-wide", count: 2
  end

  test "imprint page is publicly accessible" do
    get imprint_url

    assert_response :success
    assert_includes response.body, "SKS Erwin Russ GmbH"
    assert_includes response.body, "DE 147867476"
    assert_select ".info-page-card", count: 5
    assert_select ".info-page-list", minimum: 2
  end

  test "footer pages are publicly accessible" do
    get datenschutz_url

    assert_response :success
    assert_includes response.body, "Datenschutz"
    assert_includes response.body, "stuttgart-live.de/datenschutz"
    assert_select ".info-page-card", count: 8

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

    get barrierefreiheit_url

    assert_response :success
    assert_includes response.body, "Barrierefreiheit"
    assert_includes response.body, "digitale Barrierefreiheit"
    assert_select ".info-page-card", count: 6
  end

  test "custom static page is publicly accessible by root slug" do
    page = StaticPage.create!(
      slug: "sommer-faq",
      title: "Sommer FAQ",
      kicker: "FAQ",
      intro: "Alles zum Sommerprogramm.",
      body: "<div><h2>Anreise</h2><p>Mit der Bahn.</p></div>"
    )

    get static_page_url(page.slug)

    assert_response :success
    assert_includes response.body, "Sommer FAQ"
    assert_includes response.body, "Anreise"
    assert_includes response.body, "Mit der Bahn."
  end

  test "static pages show an edit link for authenticated backend users" do
    sign_in_as(users(:one))
    page = StaticPage.create!(
      slug: "service-faq",
      title: "Service FAQ",
      kicker: "Service",
      intro: "Hilfen und Antworten.",
      body: "<div><h2>Fragen</h2><p>Antworten.</p></div>"
    )

    get static_page_url(page.slug)

    assert_response :success
    assert_select ".info-page-hero-actions .public-edit-link[href='#{edit_backend_page_path(page)}']", text: "Edit"
  end

  test "unknown static page returns not found" do
    get "/nicht-vorhanden"

    assert_response :not_found
  end

  test "footer navigation is rendered on public pages" do
    get events_url

    assert_response :success
    assert_select "body[data-controller~='consent']"
    assert_select ".site-footer-nav a", text: "Datenschutz"
    assert_select ".site-footer-nav a", text: "Impressum"
    assert_select ".site-footer-nav a", text: "AGB"
    assert_select ".site-footer-nav a", text: "Barrierefreiheit"
    assert_select "#site-footer > .privacy-settings-button[aria-label='Datenschutzeinstellungen öffnen']", count: 1
    assert_includes response.body, "Google Analytics"
  end

  test "google analytics measurement id is only exposed on the production host" do
    with_allowed_hosts("stuttgart-live.de", "stuttgart-live.schopp3r.de") do
      host! "stuttgart-live.schopp3r.de"
      get events_path

      assert_response :success
      assert_includes response.body, 'data-controller="consent scroll-top"'
      assert_not_includes response.body, 'data-consent-measurement-id-value="G-103580617"'

      host! "stuttgart-live.de"
      get events_path

      assert_response :success
      assert_includes response.body, 'data-consent-measurement-id-value="G-103580617"'
    end
  end

  test "guardian form page is publicly accessible" do
    get begleitformular_url(event: "Test Event", venue: "Im Wizemann", date: "2026-03-10")

    assert_response :success
    assert_includes response.body, "Begleitformular"
    assert_includes response.body, "Drucken"
    assert_includes response.body, "Test Event"
  end

  private
    def with_allowed_hosts(*hosts)
      config_hosts = Rails.application.config.hosts
      previous = config_hosts.to_a.dup
      hosts.each { |host| config_hosts << host unless config_hosts.include?(host) }
      yield
    ensure
      config_hosts.clear
      previous.each { |host| config_hosts << host }
      host! "www.example.com"
    end
end
