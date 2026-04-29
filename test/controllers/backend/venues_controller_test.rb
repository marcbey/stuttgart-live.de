require "test_helper"

class Backend::VenuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @editor = users(:one)
    @venue = venues(:im_wizemann)
  end

  teardown do
    AppSetting.where(key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY).delete_all
    AppSetting.reset_cache!
  end

  test "backend user can list venues inbox" do
    sign_in_as(@editor)

    get backend_venues_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Venues"
    assert_select ".backend-split", count: 1
    assert_select "#venues_list", count: 1
    assert_select "turbo-frame#venue_editor", count: 1
    assert_includes response.body, "Im Wizemann"
    assert_select "turbo-frame#venue_editor form.editor-form", count: 1
    assert_select "turbo-frame#venue_editor input[type='hidden'][name='venue[description]']", count: 1
    assert_select "turbo-frame#venue_editor trix-editor.backend-description-editor[input='venue_description']", count: 1
    assert_select "turbo-frame#venue_editor textarea[name='venue[description]']", count: 0
    assert_select "select[name='sort'] option[selected='selected'][value='alphabetical']", count: 1
  end

  test "venues inbox can sort alphabetically" do
    sign_in_as(@editor)
    Venue.create!(name: "Aaa Venue")
    Venue.create!(name: "Zzz Venue")

    get backend_venues_url, params: { sort: "alphabetical" }

    assert_response :success
    assert_operator response.body.index("Aaa Venue"), :<, response.body.index("Im Wizemann")
    assert_operator response.body.index("Im Wizemann"), :<, response.body.index("Zzz Venue")
  end

  test "venues inbox can sort by created at" do
    sign_in_as(@editor)
    older = Venue.create!(name: "Older Venue", created_at: 2.days.ago, updated_at: 2.days.ago)
    newer = Venue.create!(name: "Newer Venue", created_at: 3.days.ago, updated_at: 1.hour.ago)

    get backend_venues_url, params: { sort: "created_at" }

    assert_response :success
    assert_operator response.body.index("Newer Venue"), :<, response.body.index("Older Venue")
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

  test "venues list exposes selectable backend url for browser history" do
    sign_in_as(@editor)

    get backend_venues_url, params: { query: "wiz", sort: "total" }

    assert_response :success
    assert_select ".venue-link[data-editor-inbox-selection-url='#{backend_venues_path(query: "wiz", sort: "total", venue_id: @venue.id)}']", count: 1
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

  test "venues inbox hides configured alias and aggregates counts into canonical venue" do
    sign_in_as(@editor)
    canonical = Venue.create!(name: "Liederhalle Beethoven-Saal")
    alias_venue = Venue.create!(name: "KKL Beethoven-Saal Stuttgart")
    create_event_for(venue: canonical, title: "Canonical Future", start_at: 2.days.from_now.change(usec: 0))
    create_event_for(venue: alias_venue, title: "Alias Past", start_at: 2.days.ago.change(usec: 0))
    configure_venue_duplicate_mapping(alias_name: alias_venue.name, canonical_name: canonical.name)

    get backend_venues_url, params: { sort: "total" }

    assert_response :success
    assert_includes response.body, "Liederhalle Beethoven-Saal"
    assert_not_includes response.body, "KKL Beethoven-Saal Stuttgart"
    assert_includes response.body, "Venue ID: #{canonical.id} · Gesamt: 2 · Kommend: 1"
  end

  test "venues inbox search by configured alias shows canonical venue" do
    sign_in_as(@editor)
    canonical = Venue.create!(name: "Liederhalle Beethoven-Saal")
    alias_venue = Venue.create!(name: "KKL Beethoven-Saal Stuttgart")
    configure_venue_duplicate_mapping(alias_name: alias_venue.name, canonical_name: canonical.name)

    get backend_venues_url, params: { query: "KKL Beethoven" }

    assert_response :success
    assert_includes response.body, "Liederhalle Beethoven-Saal"
    assert_not_includes response.body, "KKL Beethoven-Saal Stuttgart"
  end

  test "autocomplete maps configured alias query to canonical venue" do
    sign_in_as(@editor)
    canonical = Venue.create!(name: "Liederhalle Beethoven-Saal")
    alias_venue = Venue.create!(name: "KKL Beethoven-Saal Stuttgart")
    configure_venue_duplicate_mapping(alias_name: alias_venue.name, canonical_name: canonical.name)

    get autocomplete_backend_venues_url(q: "KKL Beethoven")

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal [ canonical.id ], payload.map { |item| item.fetch("id") }
    assert_equal "Liederhalle Beethoven-Saal", payload.first.fetch("name")
  end

  test "autocomplete maps similarly named configured alias to canonical venue" do
    sign_in_as(@editor)
    canonical = Venue.create!(name: "Liederhalle Beethoven-Saal")
    alias_venue = Venue.create!(name: "Liederhalle Beethovensaal")
    configure_venue_duplicate_mapping(alias_name: alias_venue.name, canonical_name: canonical.name)

    get autocomplete_backend_venues_url(q: "Liederhalle Beethovensaal")

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal [ canonical.id ], payload.map { |item| item.fetch("id") }
    assert_equal "Liederhalle Beethoven-Saal", payload.first.fetch("name")
  end

  private

  def configure_venue_duplicate_mapping(alias_name:, canonical_name:)
    AppSetting.create!(
      key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY,
      value: [
        {
          "alias" => alias_name,
          "canonical" => canonical_name,
          "alias_key" => Venue.match_key(alias_name),
          "canonical_key" => Venue.match_key(canonical_name)
        }
      ]
    )
    AppSetting.reset_cache!
  end

  def create_event_for(venue:, title:, start_at:)
    Event.create!(
      artist_name: "#{title} Artist",
      title:,
      start_at:,
      venue_record: venue,
      city: "Stuttgart",
      status: "needs_review"
    )
  end
end
