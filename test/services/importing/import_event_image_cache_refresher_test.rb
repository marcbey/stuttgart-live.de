require "test_helper"

class Importing::ImportEventImageCacheRefresherTest < ActiveSupport::TestCase
  test "attaches fetched image and marks cache as cached" do
    import_image = import_event_images(:published_cover)
    downloaded_file = Importing::RemoteImageFetcher::DownloadedFile.new(
      io: StringIO.new(solid_png_binary(width: 16, height: 12)),
      filename: "cached.png",
      content_type: "image/png"
    )

    fake_fetcher = Struct.new(:downloaded_file) do
      def call(url:)
        downloaded_file
      end
    end.new(downloaded_file)

    Importing::ImportEventImageCacheRefresher.call(import_event_image: import_image, fetcher: fake_fetcher)

    import_image.reload
    assert_predicate import_image.cached_file, :attached?
    assert_equal ImportEventImage::CACHE_STATUS_CACHED, import_image.cache_status
    assert_nil import_image.cache_error
    assert_not_nil import_image.cache_attempted_at
    assert_not_nil import_image.cached_at
  end

  test "marks cache as failed when fetching raises an error" do
    import_image = import_event_images(:published_cover)

    fake_fetcher = Struct.new(:message) do
      def call(url:)
        raise Importing::RemoteImageFetcher::FetchError, message
      end
    end.new("Bild konnte nicht geladen werden.")

    assert_raises(Importing::RemoteImageFetcher::FetchError) do
      Importing::ImportEventImageCacheRefresher.call(import_event_image: import_image, fetcher: fake_fetcher)
    end

    import_image.reload
    assert_equal ImportEventImage::CACHE_STATUS_FAILED, import_image.cache_status
    assert_equal "Bild konnte nicht geladen werden.", import_image.cache_error
    assert_not_nil import_image.cache_attempted_at
    assert_nil import_image.cached_at
  end
end
