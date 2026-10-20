module PublicImages
  # Read-only: never give a lazy variant to URL helpers, which may process it.
  module Representation
    module_function

    def transformations(size)
      dimension = EventImage::PUBLIC_VARIANT_MAX_DIMENSIONS.fetch((size || :banner_desktop).to_sym)
      result = { format: :webp, resize_to_limit: [ dimension, dimension ] }
      result[:saver] = { strip: true, quality: EventImage::WEB_QUALITY } if ActiveStorage.variant_processor == :vips
      result
    end

    def ready(attachment, size: nil)
      return unless attachment.attached?

      ready_blob(attachment.blob, transformations: transformations(size))
    end

    def ready_blob(blob, transformations:)
      return available?(blob) ? blob : nil unless blob.variable?

      digest = blob.variant(transformations).variation.digest
      record = blob.variant_records.find { |variant| variant.variation_digest == digest }
      output = record&.image&.blob
      return output if available?(output)

      blob if available?(blob)
    end

    def available?(blob)
      blob.present? && blob.service.exist?(blob.key)
    rescue ActiveStorage::FileNotFoundError, ActiveStorage::InvalidKeyError
      false
    end

    def width(representation)
      blob = representation.respond_to?(:blob) ? representation.blob : representation
      blob&.metadata&.fetch("width", nil).to_i
    end
  end
end
