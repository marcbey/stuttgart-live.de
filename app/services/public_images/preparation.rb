module PublicImages
  class Preparation
    class InvalidImage < StandardError; end
    MAX_PIXELS = 24_000_000
    MAX_BYTES = HttpFetcher::MAX_BYTES
    SIZES = %i[thumbnail card_mobile card_desktop banner_desktop].freeze

    def initialize(fetcher: HttpFetcher.new)
      @fetcher = fetcher
    end

    def call(record)
      if record.is_a?(ImportEventImage)
        prepare_import(record)
      else
        record.public_image_slots.each do |slot|
          attachment = record.public_send(slot)
          prepare_blob(attachment.blob) if attachment.attached?
        rescue InvalidImage
          next # Keep the original fallback for this slot and prepare the others.
        end
      end
    end

    private

    def prepare_import(image)
      return unless image.public_preparation_relevant?
      return prepare_blob(image.public_file.blob) if image.public_file && Representation.available?(image.public_file.blob)

      fingerprint = image.public_source_fingerprint
      response = @fetcher.call(image.image_url)
      validate_image(response.body)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(response.body), filename: "import-#{image.id}.image",
        metadata: { public_source_fingerprint: fingerprint }
      )
      prepare_blob(blob)
      image.with_lock do
        if image.public_preparation_relevant? && image.public_source_fingerprint == fingerprint
          image.prepared_file.attach(blob)
          blob = nil # Attachment now owns the source and all its variants.
        end
      end
    ensure
      blob&.purge
    end

    def prepare_blob(blob)
      raise InvalidImage, "Image exceeds byte limit" if blob.byte_size > MAX_BYTES

      blob.open { |file| validate_image(File.binread(file.path)) }
      blob.analyze unless blob.analyzed?
      SIZES.each do |size|
        variant = blob.variant(Representation.transformations(size))
        existing = blob.variant_records.find_by(variation_digest: variant.variation.digest)
        existing.destroy! if existing && !Representation.available?(existing.image.blob)
        output = variant.processed.image.blob
        output.analyze unless output.analyzed?
      end
    rescue Vips::Error, ActiveStorage::InvariableError, ImageProcessing::Error
      raise InvalidImage, "Image cannot be prepared"
    end

    def validate_image(binary)
      raise InvalidImage, "Image exceeds byte limit" if binary.bytesize > MAX_BYTES

      mime_type = Marcel::MimeType.for(StringIO.new(binary))
      raise InvalidImage, "Unsupported image format" unless %w[image/jpeg image/png image/webp image/gif].include?(mime_type)

      image = Vips::Image.new_from_buffer(binary, "", access: :sequential)
      pages = image.get_typeof("n-pages").positive? ? image.get("n-pages") : 1
      unless image.width.positive? && image.height.positive? && image.width * image.height * pages <= MAX_PIXELS
        raise InvalidImage, "Image exceeds pixel limit"
      end
    rescue Vips::Error
      raise InvalidImage, "Image cannot be read"
    end
  end
end
