module Importing
  class CacheImportEventImageJob < ApplicationJob
    queue_as :image_caching

    discard_on ActiveRecord::RecordNotFound

    retry_on Importing::RemoteImageFetcher::FetchError, wait: 2.minutes, attempts: 3 do |job, error|
      import_event_image = ImportEventImage.find_by(id: job.arguments.first)
      next unless import_event_image.present?

      import_event_image.update_columns(
        cache_status: ImportEventImage::CACHE_STATUS_FAILED,
        cache_attempted_at: Time.current,
        cached_at: nil,
        cache_error: error.message,
        updated_at: Time.current
      )
    end

    def perform(import_event_image_id, expected_image_url = nil)
      import_event_image = ImportEventImage.find(import_event_image_id)
      return if expected_image_url.present? && import_event_image.image_url != expected_image_url
      return if import_event_image.cached?

      Importing::ImportEventImageCacheRefresher.call(import_event_image:)
    end
  end
end
