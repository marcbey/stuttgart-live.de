require "test_helper"

class Backend::PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @editor = users(:one)
    @admin = users(:two)
    @blogger = users(:blogger)
    StaticPageDefaults.ensure!
  end

  test "requires authentication" do
    get backend_pages_url

    assert_redirected_to new_session_url
  end

  test "blogger cannot access pages backend" do
    sign_in_as(@blogger)

    get backend_pages_url

    assert_redirected_to root_url
  end

  test "editor can access pages index" do
    sign_in_as(@editor)
    custom_page = StaticPage.create!(
      slug: "hausordnung",
      title: "Hausordnung",
      intro: "Wichtige Hinweise.",
      body: "<div>Keine Glasflaschen.</div>"
    )

    get backend_pages_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Seiten"
    assert_includes response.body, "Alle Seiten werden hier zentral gepflegt."
    assert_includes response.body, custom_page.title
    assert_includes response.body, "Kontakt"
    assert_includes response.body, "/#{custom_page.slug}"
    assert_no_match(/Systemseiten|Eigene Seiten/, response.body)
    assert_no_match(/>System</, response.body)
  end

  test "editor can open edit form for system page" do
    sign_in_as(@editor)
    page = StaticPage.find_by!(slug: "kontakt")

    get edit_backend_page_url(page)

    assert_response :success
    assert_select "form.editor-form[action='#{backend_page_path(page)}']"
    assert_select "input[name='static_page[slug]'][disabled]", count: 1
    assert_includes response.body, "Systemseiten behalten ihren festen Slug."
  end

  test "editor can create a page" do
    sign_in_as(@editor)

    assert_difference -> { StaticPage.count }, 1 do
      post backend_pages_url, params: {
        static_page: {
          title: "FAQ Festival",
          slug: "faq-festival",
          kicker: "FAQ",
          intro: "Fragen und Antworten.",
          body: "<div><p>Alle Infos.</p></div>"
        }
      }
    end

    page = StaticPage.order(:id).last

    assert_redirected_to edit_backend_page_url(page)
    assert_equal "FAQ Festival", page.title
    assert_equal "FAQ", page.kicker
    assert_equal "Alle Infos.", page.body.to_plain_text.strip
  end

  test "admin can update a system page" do
    sign_in_as(@admin)
    page = StaticPage.find_by!(slug: "kontakt")

    patch backend_page_url(page), params: {
      static_page: {
        title: "Kontakt & Service",
        slug: page.slug,
        kicker: "Service",
        intro: "Schnelle Wege zu allen Ansprechpartnern.",
        body: "<div><p>Neue Kontaktinfos.</p></div>"
      }
    }

    assert_redirected_to edit_backend_page_url(page)
    assert_equal "Kontakt & Service", page.reload.title
    assert_equal "Neue Kontaktinfos.", page.body.to_plain_text.strip
  end

  test "editor can delete a custom page" do
    sign_in_as(@editor)
    page = StaticPage.create!(
      slug: "anfahrt",
      title: "Anfahrt",
      body: "<div>Mit Bus und Bahn.</div>"
    )

    assert_difference -> { StaticPage.count }, -1 do
      delete backend_page_url(page)
    end

    assert_redirected_to backend_pages_url
  end

  test "system page cannot be deleted" do
    sign_in_as(@admin)
    page = StaticPage.find_by!(slug: "impressum")

    assert_no_difference -> { StaticPage.count } do
      delete backend_page_url(page)
    end

    assert_redirected_to backend_pages_url
    assert_equal "Systemseiten können nicht gelöscht werden", flash[:alert]
  end
end
