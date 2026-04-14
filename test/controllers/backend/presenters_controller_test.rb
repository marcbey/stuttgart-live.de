require "test_helper"

class Backend::PresentersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @editor = users(:one)
    @presenter = create_presenter(name: "Live Nation")
  end

  test "backend user can list presenters in inbox layout" do
    sign_in_as(@editor)

    get backend_presenters_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Präsentatoren"
    assert_includes response.body, "Live Nation"
    assert_includes response.body, @presenter.external_url
    assert_select ".backend-split", count: 1
    assert_select "#presenters_list", count: 1
    assert_select "turbo-frame#presenter_editor", count: 1
  end

  test "presenters inbox hides new button while a new presenter is selected" do
    sign_in_as(@editor)

    get backend_presenters_url(new: "1")

    assert_response :success
    assert_select "#presenter_topbar_editor_actions button[form='editor_form_presenter']", text: "Save", count: 1
    assert_select "a.button", text: "New", count: 0
    assert_select "a.button", text: "Import Logos", count: 1
  end

  test "presenter search is case insensitive" do
    sign_in_as(@editor)
    create_presenter(name: "Jazz House")

    get backend_presenters_url, params: { query: "LIVE" }

    assert_response :success
    assert_includes response.body, "Live Nation"
    assert_not_includes response.body, "Jazz House"
  end

  test "backend user can render presenter pages with svg logos" do
    presenter = Presenter.new(
      name: "SVG Nation",
      external_url: "https://example.com/svg-nation"
    )
    presenter.logo.attach(create_svg_blob(filename: "svg-nation.svg"))
    presenter.save!

    sign_in_as(@editor)

    get backend_presenters_url

    assert_response :success
    assert_includes response.body, "SVG Nation"

    get edit_backend_presenter_url(presenter), headers: { "Turbo-Frame" => "presenter_editor" }

    assert_response :success
    assert_select "turbo-frame#presenter_editor"
    assert_includes response.body, "SVG Nation"
  end

  test "presenter editor shows linked events" do
    sign_in_as(@editor)
    event = events(:published_one)
    event.event_presenters.create!(presenter: @presenter, position: 1)

    get backend_presenters_url(presenter_id: @presenter.id)

    assert_response :success
    assert_select "h3", text: "Verknüpfte Events"
    assert_includes response.body, event.artist_name
    assert_select "a.presenter-linked-event-link[href='#{backend_events_path(status: event.status, event_id: event.id)}']", count: 1
  end

  test "edit redirects to inbox state" do
    sign_in_as(@editor)

    get edit_backend_presenter_url(@presenter, query: "live")

    assert_redirected_to backend_presenters_url(query: "live", presenter_id: @presenter.id)
  end

  test "backend user can create presenter" do
    sign_in_as(@editor)

    assert_difference -> { Presenter.count }, 1 do
      post backend_presenters_url, params: {
        presenter: {
          name: "DreamHaus",
          external_url: "https://example.com/dreamhaus",
          description: "Optionaler Text",
          logo: png_upload(filename: "dreamhaus.png")
        }
      }
    end

    presenter = Presenter.order(:id).last
    assert_redirected_to backend_presenters_url(presenter_id: presenter.id)
    assert_equal "DreamHaus", presenter.name
  end

  test "backend user can create presenter without external url" do
    sign_in_as(@editor)

    assert_difference -> { Presenter.count }, 1 do
      post backend_presenters_url, params: {
        presenter: {
          name: "Ohne Link",
          description: "Nur mit Logo",
          logo: png_upload(filename: "ohne-link.png")
        }
      }
    end

    presenter = Presenter.order(:id).last
    assert_redirected_to backend_presenters_url(presenter_id: presenter.id)
    assert_nil presenter.external_url
  end

  test "turbo update refreshes presenters list and editor" do
    sign_in_as(@editor)

    patch backend_presenter_url(@presenter), params: {
      query: "live",
      presenter: {
        name: "Live Nation Updated",
        external_url: "https://example.com/live-nation-updated",
        description: "Neue Beschreibung"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'target="flash-messages"'
    assert_includes response.body, 'target="presenters_list"'
    assert_includes response.body, 'target="presenter_editor"'
    assert_equal "Live Nation Updated", @presenter.reload.name
  end

  test "backend user can render bulk upload page" do
    sign_in_as(@editor)

    get bulk_new_backend_presenters_url

    assert_response :success
    assert_includes response.body, "Präsentatoren gesammelt importieren"
    assert_includes response.body, "Mehrere Logos auswählen"
    assert_includes response.body, "Verzeichnis auswählen"
  end

  test "backend user can bulk create presenters from multiple logos" do
    sign_in_as(@editor)

    assert_difference -> { Presenter.count }, 2 do
      post bulk_create_backend_presenters_url, params: {
        presenter_logos: [
          png_upload(filename: "foo-bar.png"),
          png_upload(filename: "ACME_Booking.png")
        ]
      }
    end

    assert_redirected_to backend_presenters_url
    assert_equal [ "ACME Booking", "foo bar" ].sort, Presenter.order(:id).last(2).map(&:name).sort
  end

  test "bulk upload updates existing presenter logo and keeps metadata" do
    sign_in_as(@editor)
    @presenter.update!(description: "Bestehende Beschreibung")
    original_blob_id = @presenter.logo.blob.id

    assert_no_difference -> { Presenter.count } do
      post bulk_create_backend_presenters_url, params: {
        presenter_logos: [ png_upload(filename: "live_nation.png", rgb: [ 12, 34, 56 ]) ]
      }
    end

    assert_redirected_to backend_presenters_url
    @presenter.reload
    assert_equal "https://example.com/live-nation", @presenter.external_url
    assert_equal "Bestehende Beschreibung", @presenter.description
    assert_not_equal original_blob_id, @presenter.logo.blob.id
  end

  test "bulk upload rerenders when no files were selected" do
    sign_in_as(@editor)

    assert_no_difference -> { Presenter.count } do
      post bulk_create_backend_presenters_url
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Bitte mindestens eine Datei auswählen."
  end

  test "bulk upload rerenders when existing presenter name is ambiguous" do
    sign_in_as(@editor)
    duplicate_presenter = Presenter.new(name: "live nation")
    duplicate_presenter.logo.attach(create_uploaded_blob(filename: "live-nation-duplicate.png"))
    duplicate_presenter.save!

    assert_no_difference -> { Presenter.count } do
      post bulk_create_backend_presenters_url, params: {
        presenter_logos: [ png_upload(filename: "live_nation.png") ]
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Mehrdeutiger vorhandener Präsentator-Name"
  end

  test "create rerenders inbox form when logo is missing" do
    sign_in_as(@editor)

    assert_no_difference -> { Presenter.count } do
      post backend_presenters_url, params: {
        presenter: {
          name: "Ohne Logo",
          external_url: "https://example.com/ohne-logo"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "#presenters_list", count: 1
    assert_select "turbo-frame#presenter_editor", count: 1
    assert_includes response.body, "muss hochgeladen werden"
  end

  test "destroy shows message when presenter is still assigned" do
    sign_in_as(@editor)
    events(:published_one).event_presenters.create!(presenter: @presenter, position: 1)

    assert_no_difference -> { Presenter.count } do
      delete backend_presenter_url(@presenter)
    end

    assert_redirected_to backend_presenters_url
    follow_redirect!
    assert_includes response.body, "Präsentator ist noch Events zugeordnet und kann nicht gelöscht werden."
  end

  private

  def create_presenter(name:)
    presenter = Presenter.new(
      name: name,
      external_url: "https://example.com/#{name.parameterize}"
    )
    presenter.logo.attach(create_uploaded_blob(filename: "#{name.parameterize}.png"))
    presenter.save!
    presenter
  end

  def create_svg_blob(filename:)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(<<~SVG),
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
          <rect width="16" height="16" fill="#000"/>
        </svg>
      SVG
      filename:,
      content_type: "image/svg+xml"
    )
  end
end
