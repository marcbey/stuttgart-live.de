require "test_helper"

class EventImageTest < ActiveSupport::TestCase
  setup do
    @event = events(:needs_review_one)
    @fixture_path = Rails.root.join("test/fixtures/files/test_image.png")
  end

  test "valid slider image with attached file" do
    image = build_image(purpose: EventImage::PURPOSE_SLIDER)

    assert image.valid?
  end

  test "detail hero is unique per event" do
    build_image(
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      event: @event
    ).save!

    duplicate = build_image(
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      event: @event
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:purpose], "darf nur einmal pro Event als Detail-Hero vorkommen"
  end

  test "grid tile requires grid variant" do
    image = build_image(
      purpose: EventImage::PURPOSE_GRID_TILE,
      grid_variant: nil
    )

    assert_not image.valid?
    assert_includes image.errors[:grid_variant], "muss für Grid-Bilder gesetzt sein"
  end

  test "grid variant must be unique per event" do
    build_image(
      purpose: EventImage::PURPOSE_GRID_TILE,
      grid_variant: EventImage::GRID_VARIANT_1X2
    ).save!

    duplicate = build_image(
      purpose: EventImage::PURPOSE_GRID_TILE,
      grid_variant: EventImage::GRID_VARIANT_1X2
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:grid_variant], "ist für dieses Event bereits belegt"
  end

  test "non image uploads are rejected" do
    image = EventImage.new(event: @event, purpose: EventImage::PURPOSE_SLIDER)
    image.file.attach(
      io: StringIO.new("not an image"),
      filename: "not-image.txt",
      content_type: "text/plain"
    )

    assert_not image.valid?
    assert_includes image.errors[:file], "muss ein Bild sein"
  end

  private

  def build_image(event: @event, purpose:, grid_variant: nil)
    image = EventImage.new(
      event: event,
      purpose: purpose,
      grid_variant: grid_variant,
      alt_text: "Alt",
      sub_text: "Sub"
    )
    binary = File.binread(@fixture_path)
    image.file.attach(
      io: StringIO.new(binary),
      filename: "test_image.png",
      content_type: "image/png"
    )
    image
  end
end
