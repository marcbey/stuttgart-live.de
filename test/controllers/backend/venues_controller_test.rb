require "test_helper"

class Backend::VenuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @editor = users(:one)
    @venue = venues(:im_wizemann)
  end

  test "backend user can list venues" do
    sign_in_as(@editor)

    get backend_venues_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Venues"
    assert_includes response.body, "Suche nach Name, Adresse, Beschreibung oder URL"
    assert_not_includes response.body, "Im Wizemann"
  end

  test "backend user can search venues" do
    sign_in_as(@editor)

    get backend_venues_url, params: { query: "wiz" }

    assert_response :success
    assert_includes response.body, "Im Wizemann"
    assert_includes response.body, "Kommend"
    assert_includes response.body, "Adresse"
    assert_not_includes response.body, "LKA Longhorn"
  end

  test "backend user can search venues via turbo stream" do
    sign_in_as(@editor)

    get backend_venues_url, params: { query: "lka" }, as: :turbo_stream

    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes response.body, "turbo-stream"
    assert_includes response.body, "LKA Longhorn"
    assert_not_includes response.body, "event-list-count"
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
    assert_redirected_to edit_backend_venue_url(created_venue)
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

    assert_redirected_to edit_backend_venue_url(@venue)
    @venue.reload
    assert_equal "Im Wizemann Club", @venue.name
    assert_equal "Neue Adresse", @venue.address
    assert_equal "Venue wurde gespeichert.", flash[:notice]
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

    assert_redirected_to edit_backend_venue_url(@venue)
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
end
