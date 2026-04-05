module Importing
  class ImportEventImageCacheRefresher
    def self.call(import_event_image:, fetcher: RemoteImageFetcher)
      new(import_event_image:, fetcher:).call
    end

    def initialize(import_event_image:, fetcher:)
      @import_event_image = import_event_image
      @fetcher = fetcher
    end

    def call
      source_url = import_event_image.image_url.to_s
      return if source_url.blank?

      downloaded_file = fetcher.call(url: source_url)

      import_event_image.with_lock do
        import_event_image.reload
        return if import_event_image.image_url != source_url

        import_event_image.cached_file.attach(
          io: downloaded_file.io,
          filename: downloaded_file.filename,
          content_type: downloaded_file.content_type
        )
        import_event_image.update!(
          cache_status: ImportEventImage::CACHE_STATUS_CACHED,
          cache_attempted_at: Time.current,
          cached_at: Time.current,
          cache_error: nil
        )
      end
    rescue Importing::RemoteImageFetcher::FetchError => error
      mark_failed!(error.message)
      raise
    end

    private

    attr_reader :fetcher, :import_event_image

    def mark_failed!(message)
      return unless import_event_image.persisted?

      import_event_image.update_columns(
        cache_status: ImportEventImage::CACHE_STATUS_FAILED,
        cache_attempted_at: Time.current,
        cached_at: nil,
        cache_error: message,
        updated_at: Time.current
      )
    end
  end
end
