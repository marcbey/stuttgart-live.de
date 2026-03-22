require "test_helper"

class Backend::PresentersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @editor = users(:one)
    @presenter = create_presenter(name: "Live Nation")
  end

  test "backend user can list presenters" do
    sign_in_as(@editor)

    get backend_presenters_url

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Präsentatoren"
    assert_includes response.body, "Live Nation"
    assert_includes response.body, @presenter.external_url
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

    get edit_backend_presenter_url(presenter)

    assert_response :success
    assert_includes response.body, "SVG Nation"
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

    assert_redirected_to backend_presenters_url
    assert_equal "DreamHaus", Presenter.order(:id).last.name
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

    assert_redirected_to backend_presenters_url
    assert_nil Presenter.order(:id).last.external_url
  end

  test "create rerenders form when logo is missing" do
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
    assert_includes response.body, "muss hochgeladen werden"
  end

  test "backend user can update presenter" do
    sign_in_as(@editor)

    patch backend_presenter_url(@presenter), params: {
      presenter: {
        name: "Live Nation Updated",
        external_url: "https://example.com/live-nation-updated",
        description: "Neue Beschreibung"
      }
    }

    assert_redirected_to backend_presenters_url
    @presenter.reload
    assert_equal "Live Nation Updated", @presenter.name
    assert_equal "Neue Beschreibung", @presenter.description
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
