require "test_helper"

class Importing::CacheImportEventImageJobTest < ActiveJob::TestCase
  test "enqueues on dedicated queue" do
    assert_equal "image_caching", Importing::CacheImportEventImageJob.queue_name
  end

  test "caches fetched import image" do
    import_image = import_event_images(:published_cover)
    downloaded_file = Importing::RemoteImageFetcher::DownloadedFile.new(
      io: StringIO.new(solid_png_binary(width: 24, height: 24)),
      filename: "cached.png",
      content_type: "image/png"
    )

    fetcher_singleton = Importing::RemoteImageFetcher.singleton_class
    original_call = Importing::RemoteImageFetcher.method(:call)

    fetcher_singleton.define_method(:call, ->(url:) { downloaded_file })
    begin
      Importing::CacheImportEventImageJob.perform_now(import_image.id, import_image.image_url)
    ensure
      fetcher_singleton.define_method(:call, original_call)
    end

    assert_equal ImportEventImage::CACHE_STATUS_CACHED, import_image.reload.cache_status
    assert_predicate import_image.cached_file, :attached?
  end
end
