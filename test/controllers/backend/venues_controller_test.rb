require "test_helper"

class Backend::VenuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @editor = users(:one)
    @venue = venues(:im_wizemann)
  end

  test "backend user can list venues inbox" do
    sign_in_as(@editor)

    get backend_venues_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Venues"
    assert_includes response.body, "Suche nach Name, Adresse, Beschreibung oder URL"
    assert_select ".backend-split", count: 1
    assert_select "#venues_list", count: 1
    assert_select "turbo-frame#venue_editor", count: 1
    assert_not_includes response.body, "Im Wizemann"
  end

  test "venues inbox hides new button while a new venue is selected" do
    sign_in_as(@editor)

    get backend_venues_url(new: "1")

    assert_response :success
    assert_select "#venue_topbar_editor_actions button[form='editor_form_venue']", text: "Save", count: 1
    assert_select "a.button", text: "New", count: 0
  end

  test "backend user can search venues and load selected editor" do
    sign_in_as(@editor)

    get backend_venues_url, params: { query: "wiz" }

    assert_response :success
    assert_includes response.body, "Im Wizemann"
    assert_includes response.body, "Kommend"
    assert_includes response.body, "Adresse"
    assert_not_includes response.body, "LKA Longhorn"
    assert_select "turbo-frame#venue_editor form.editor-form", count: 1
  end

  test "backend user can search venues via turbo stream" do
    sign_in_as(@editor)

    get backend_venues_url, params: { query: "lka" }, as: :turbo_stream

    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes response.body, 'target="venues_list"'
    assert_includes response.body, 'target="venue_editor"'
    assert_includes response.body, "LKA Longhorn"
  end

  test "edit redirects to inbox state" do
    sign_in_as(@editor)

    get edit_backend_venue_url(@venue, query: "wiz")

    assert_redirected_to backend_venues_url(query: "wiz", venue_id: @venue.id)
  end

  test "turbo frame edit renders editor panel" do
    sign_in_as(@editor)

    get edit_backend_venue_url(@venue, query: "wiz"), headers: { "Turbo-Frame" => "venue_editor" }

    assert_response :success
    assert_select "turbo-frame#venue_editor"
    assert_select ".editor-panel.backend-panel[data-selected-item-id='#{@venue.id}']"
    assert_select "form.editor-form[action='#{backend_venue_path(@venue)}']"
  end

  test "backend user can create venue" do
    sign_in_as(@editor)

    assert_difference -> { Venue.count }, 1 do
      post backend_venues_url, params: {
        venue: {
          name: "Porsche Arena",
          external_url: "https://example.com/porsche-arena",
          address: "Mercedesstraße 69, 70372 Stuttgart",
          description: "Große Venue"
        }
      }
    end

    created_venue = Venue.order(:id).last
    assert_redirected_to backend_venues_url(venue_id: created_venue.id)
    assert_equal "Porsche Arena", created_venue.name
  end

  test "backend user can update venue" do
    sign_in_as(@editor)

    patch backend_venue_url(@venue), params: {
      venue: {
        name: "Im Wizemann Club",
        external_url: "https://example.com/wizemann-club",
        address: "Neue Adresse",
        description: "Neue Beschreibung"
      }
    }

    assert_redirected_to backend_venues_url(venue_id: @venue.id)
    @venue.reload
    assert_equal "Im Wizemann Club", @venue.name
    assert_equal "Neue Adresse", @venue.address
    assert_equal "Venue wurde gespeichert.", flash[:notice]
  end

  test "turbo update refreshes venues list and editor" do
    sign_in_as(@editor)

    patch backend_venue_url(@venue), params: {
      query: "wiz",
      venue: {
        name: "Im Wizemann Club",
        external_url: "https://example.com/wizemann-club",
        address: "Neue Adresse",
        description: "Neue Beschreibung"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'target="flash-messages"'
    assert_includes response.body, 'target="venues_list"'
    assert_includes response.body, 'target="venue_editor"'
    assert_equal "Im Wizemann Club", @venue.reload.name
  end

  test "backend user can remove venue logo" do
    sign_in_as(@editor)
    @venue.logo.attach(
      io: file_fixture("test_image.png").open,
      filename: "test_image.png",
      content_type: "image/png"
    )

    patch backend_venue_url(@venue), params: {
      venue: {
        remove_logo: "1"
      }
    }

    assert_redirected_to backend_venues_url(venue_id: @venue.id)
    @venue.reload
    assert_not @venue.logo.attached?
  end

  test "autocomplete returns matching venues" do
    sign_in_as(@editor)

    get autocomplete_backend_venues_url(q: "wiz")

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal [ @venue.id ], payload.map { |item| item.fetch("id") }
    assert_equal "Im Wizemann", payload.first.fetch("name")
  end

  test "autocomplete ignores punctuation differences in venue names" do
    sign_in_as(@editor)
    first = Venue.create!(name: "Goldmark's")
    second = Venue.create!(name: "Goldmark´s Stuttgart")

    get autocomplete_backend_venues_url(q: "goldmarks")

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal [ first.id, second.id ], payload.map { |item| item.fetch("id") }
  end
end
