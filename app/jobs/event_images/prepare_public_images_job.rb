module EventImages
  class PreparePublicImagesJob < ApplicationJob
    queue_as :public_images
    limits_concurrency to: 1, key: "public-images", group: "public-images", duration: 5.minutes

    discard_on ActiveJob::DeserializationError
    retry_on PublicImages::HostLock::Busy, wait: 30.seconds, attempts: 20
    retry_on GuardedHttpFetcher::Error, ActiveStorage::FileNotFoundError, wait: 1.minute, attempts: 3
    discard_on GuardedHttpFetcher::NotFound
    discard_on PublicImages::Preparation::InvalidImage

    def perform(record)
      PublicImages::HostLock.new.synchronize { PublicImages::Preparation.new.call(record) }
    end
  end
end
