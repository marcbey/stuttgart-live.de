require "test_helper"

module EventImages
  class PreprocessPressVariantsJobTest < ActiveJob::TestCase
    setup do
      @event = events(:needs_review_one)
    end

    test "preprocesses all press variants for slider image" do
      image = build_image(purpose: EventImage::PURPOSE_SLIDER)
      processed_sizes = []
      image.define_singleton_method(:processed_press_variant) do |size|
        processed_sizes << size
      end

      PreprocessPressVariantsJob.perform_now(image)

      assert_equal EventImage::PRESS_VARIANT_MAX_DIMENSIONS.keys, processed_sizes
    end

    test "skips non slider image" do
      image = build_image(purpose: EventImage::PURPOSE_DETAIL_HERO)
      image.define_singleton_method(:processed_press_variant) do |_size|
        raise "should not process press variants for detail hero image"
      end

      PreprocessPressVariantsJob.perform_now(image)

      assert true
    end

    test "skips slider image without attachment" do
      image = EventImage.new(event: @event, purpose: EventImage::PURPOSE_SLIDER)
      image.define_singleton_method(:processed_press_variant) do |_size|
        raise "should not process press variants without attachment"
      end

      PreprocessPressVariantsJob.perform_now(image)

      assert true
    end

    test "keeps processing errors visible" do
      image = build_image(purpose: EventImage::PURPOSE_SLIDER)
      image.define_singleton_method(:processed_press_variant) do |_size|
        raise EventImage::ProcessingError, "Bild konnte nicht verarbeitet werden."
      end

      assert_raises(EventImage::ProcessingError) do
        PreprocessPressVariantsJob.perform_now(image)
      end
    end

    private

    def build_image(purpose:)
      image = @event.event_images.new(purpose: purpose)
      image.file.attach(
        io: StringIO.new(solid_png_binary(width: 20, height: 20)),
        filename: "test.png",
        content_type: "image/png"
      )
      image.save!
      image
    end
  end
end
