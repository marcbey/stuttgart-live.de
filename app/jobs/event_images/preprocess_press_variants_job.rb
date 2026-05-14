module EventImages
  class PreprocessPressVariantsJob < ApplicationJob
    queue_as :default

    discard_on ActiveJob::DeserializationError

    def perform(event_image)
      return unless event_image.slider?
      return unless event_image.file.attached?

      EventImage::PRESS_VARIANT_MAX_DIMENSIONS.each_key do |size|
        event_image.processed_press_variant(size)
      end
    end
  end
end
