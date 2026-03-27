require "test_helper"

class PresenterTest < ActiveSupport::TestCase
  test "requires name and logo" do
    presenter = Presenter.new

    assert_not presenter.valid?
    assert presenter.errors.added?(:name, :blank)
    assert_includes presenter.errors[:logo], "muss hochgeladen werden"
  end

  test "allows blank external url" do
    presenter = Presenter.new(name: "Ohne Link")
    presenter.logo.attach(create_uploaded_blob(filename: "ohne-link.png"))

    assert presenter.valid?
  end

  test "accepts only http and https urls" do
    presenter = Presenter.new(
      name: "Test Presenter",
      external_url: "ftp://example.com"
    )
    presenter.logo.attach(create_uploaded_blob(filename: "presenter.png"))

    assert_not presenter.valid?
    assert_includes presenter.errors[:external_url], "muss mit http:// oder https:// beginnen"
  end

  test "uses the original logo for svg previews" do
    presenter = Presenter.new(name: "SVG Presenter")
    presenter.logo.attach(create_svg_blob(filename: "presenter.svg"))

    assert presenter.valid?
    assert_same presenter.logo, presenter.thumbnail_logo_variant
    assert_same presenter.logo, presenter.detail_logo_variant
  end

  test "falls back to the original logo when variant processing is unavailable" do
    presenter = create_presenter(name: "Fallback Presenter")
    failing_representation = Object.new
    failing_representation.define_singleton_method(:processed) do
      raise MiniMagick::Error, "executable not found: convert"
    end

    presenter.define_singleton_method(:logo_representation) do |resize_to_limit:|
      failing_representation
    end

    assert_same presenter.logo, presenter.thumbnail_logo_variant
    assert_same presenter.logo, presenter.detail_logo_variant
  end

  test "serves svg logos inline" do
    assert_includes Rails.application.config.active_storage.content_types_allowed_inline, "image/svg+xml"
    assert_not_includes Rails.application.config.active_storage.content_types_to_serve_as_binary, "image/svg+xml"
  end

  test "prevents deleting presenters that are still assigned to events" do
    presenter = create_presenter(name: "Bound Presenter")
    event = events(:published_one)
    event.event_presenters.create!(presenter:, position: 1)

    assert_no_difference -> { Presenter.count } do
      assert_not presenter.destroy
    end

    assert presenter.errors[:base].any?
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
