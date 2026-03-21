require "test_helper"

class EventPresenterTest < ActiveSupport::TestCase
  test "requires unique presenter and unique position per event" do
    presenter_one = create_presenter(name: "One")
    presenter_two = create_presenter(name: "Two")
    event = events(:published_one)

    event.event_presenters.create!(presenter: presenter_one, position: 1)

    duplicate_presenter = event.event_presenters.build(presenter: presenter_one, position: 2)
    duplicate_position = event.event_presenters.build(presenter: presenter_two, position: 1)

    assert_not duplicate_presenter.valid?
    assert duplicate_presenter.errors.added?(:presenter_id, :taken, value: presenter_one.id)

    assert_not duplicate_position.valid?
    assert duplicate_position.errors.added?(:position, :taken, value: 1)
  end

  test "event ordered_presenters follow join position" do
    presenter_one = create_presenter(name: "First")
    presenter_two = create_presenter(name: "Second")
    event = events(:published_one)

    event.event_presenters.create!(presenter: presenter_two, position: 2)
    event.event_presenters.create!(presenter: presenter_one, position: 1)

    assert_equal [ presenter_one, presenter_two ], event.reload.ordered_presenters
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
