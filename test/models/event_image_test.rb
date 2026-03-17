require "test_helper"
require "vips"

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

  test "detail hero allows grid variant" do
    image = build_image(
      purpose: EventImage::PURPOSE_DETAIL_HERO,
      grid_variant: EventImage::GRID_VARIANT_1X2
    )

    assert image.valid?
  end

  test "slider rejects grid variant" do
    image = build_image(
      purpose: EventImage::PURPOSE_SLIDER,
      grid_variant: EventImage::GRID_VARIANT_1X2
    )

    assert_not image.valid?
    assert_includes image.errors[:grid_variant], "ist nur für das Eventbild erlaubt"
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

  test "optimized variant scales down to web size and keeps original blob" do
    image = EventImage.new(event: @event, purpose: EventImage::PURPOSE_DETAIL_HERO)
    original_binary = large_test_image_binary(width: 2000, height: 1500)

    image.file.attach(
      io: StringIO.new(original_binary),
      filename: "large-test-image.png",
      content_type: "image/png"
    )
    image.save!

    optimized_binary = image.processed_optimized_variant.image.download
    optimized_image = Vips::Image.new_from_buffer(optimized_binary, "")
    original_image = Vips::Image.new_from_buffer(image.file.download, "")

    assert_equal 1280, optimized_image.width
    assert_equal 960, optimized_image.height
    assert_equal 2000, original_image.width
    assert_equal 1500, original_image.height
    assert_equal original_binary, image.file.download
  end

  test "optimized variant raises a processing error for broken image payloads" do
    image = EventImage.new(event: @event, purpose: EventImage::PURPOSE_SLIDER)
    image.file.attach(
      io: StringIO.new("broken-image-data"),
      filename: "broken-image.png",
      content_type: "image/png"
    )
    image.save!

    error = assert_raises(EventImage::ProcessingError) do
      image.processed_optimized_variant
    end

    assert_includes error.message, "Bild konnte nicht für Web und Mobile optimiert werden."
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

  def large_test_image_binary(width:, height:)
    Vips::Image.black(width, height).write_to_buffer(".png")
  end
end
