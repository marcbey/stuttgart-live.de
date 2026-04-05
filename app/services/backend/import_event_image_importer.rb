require "stringio"

module Backend
  class ImportEventImageImporter
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
      return cached_downloaded_file if @import_event_image.cached?

      Importing::RemoteImageFetcher.call(url:)
    rescue Importing::RemoteImageFetcher::FetchError => error
      raise error.message
    end

    def cached_downloaded_file
      Importing::RemoteImageFetcher::DownloadedFile.new(
        io: StringIO.new(@import_event_image.cached_file.download),
        filename: @import_event_image.cached_file.filename.to_s,
        content_type: @import_event_image.cached_file.content_type.to_s.presence || "image/jpeg"
      )
    end

    def default_alt_text
      [ @event.artist_name, @event.title ].compact.join(" - ").presence
    end
  end
end
