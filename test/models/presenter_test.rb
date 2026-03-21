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
end
