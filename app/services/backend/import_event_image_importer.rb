require "net/http"
require "stringio"
require "uri"

module Backend
  class ImportEventImageImporter
    DownloadedFile = Struct.new(:io, :filename, :content_type, keyword_init: true)

    def self.call(event:, import_event_image:, purpose:, grid_variant: nil)
      new(
        event: event,
        import_event_image: import_event_image,
        purpose: purpose,
        grid_variant: grid_variant
      ).call
    end

    def initialize(event:, import_event_image:, purpose:, grid_variant:)
      @event = event
      @import_event_image = import_event_image
      @purpose = purpose.to_s
      @grid_variant = grid_variant.to_s.presence
    end

    def call
      downloaded_file = download_file(@import_event_image.image_url)

      event_image = @event.event_images.new(
        purpose: @purpose,
        grid_variant: @grid_variant,
        alt_text: default_alt_text
      )
      event_image.file.attach(
        io: downloaded_file.io,
        filename: downloaded_file.filename,
        content_type: downloaded_file.content_type
      )
      event_image.save!
      event_image
    end

    private

    def download_file(url)
      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)
      raise "Bild konnte nicht geladen werden (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)

      DownloadedFile.new(
        io: StringIO.new(response.body),
        filename: filename_for(uri),
        content_type: response.content_type.presence || "image/jpeg"
      )
    rescue URI::InvalidURIError => e
      raise "Ungültige Bild-URL: #{e.message}"
    end

    def filename_for(uri)
      basename = File.basename(uri.path.to_s)
      return basename if basename.present? && basename != "/"

      "import-image"
    end

    def default_alt_text
      [ @event.artist_name, @event.title ].compact.join(" - ").presence
    end
  end
end
