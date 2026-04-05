require "test_helper"

class Events::Maintenance::ImportImageCacheWarmerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
  end

  test "enqueues uncached images for published events by default" do
    published_image = import_event_images(:published_cover)
    unpublished_event = Event.create!(
      title: "Unpublished cache event",
      artist_name: "Unpublished Artist",
      start_at: Time.zone.local(2026, 8, 1, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )
    unpublished_event.import_event_images.create!(
      source: "eventim",
      image_type: "large",
      image_url: "https://example.com/unpublished.jpg",
      role: "cover",
      aspect_hint: "landscape"
    )

    result = nil
    assert_enqueued_jobs 1, only: Importing::CacheImportEventImageJob do
      result = Events::Maintenance::ImportImageCacheWarmer.call
    end

    assert_equal 1, result.images_scanned
    assert_equal 1, result.images_eligible
    assert_equal 1, result.jobs_enqueued
    assert_equal [ published_image.id ], enqueued_jobs.filter_map { |job| job[:args].first }
  end

  test "skips cached images" do
    image = import_event_images(:published_cover)
    image.cached_file.attach(create_uploaded_blob(filename: "warm-cached.png"))
    image.update!(
      cache_status: ImportEventImage::CACHE_STATUS_CACHED,
      cache_attempted_at: Time.current,
      cached_at: Time.current
    )

    result = nil
    assert_enqueued_jobs 0, only: Importing::CacheImportEventImageJob do
      result = Events::Maintenance::ImportImageCacheWarmer.call
    end

    assert_equal 1, result.images_scanned
    assert_equal 1, result.images_skipped_cached
    assert_equal 0, result.jobs_enqueued
  end

  test "includes failed images only when requested" do
    image = import_event_images(:published_cover)
    image.update!(
      cache_status: ImportEventImage::CACHE_STATUS_FAILED,
      cache_attempted_at: 5.minutes.ago,
      cache_error: "timeout"
    )

    default_result = nil
    assert_enqueued_jobs 0, only: Importing::CacheImportEventImageJob do
      default_result = Events::Maintenance::ImportImageCacheWarmer.call
    end

    assert_equal 1, default_result.images_skipped_failed

    clear_enqueued_jobs

    include_failed_result = nil
    assert_enqueued_jobs 1, only: Importing::CacheImportEventImageJob do
      include_failed_result = Events::Maintenance::ImportImageCacheWarmer.call(include_failed: true)
    end

    assert_equal 1, include_failed_result.images_eligible
    assert_equal 1, include_failed_result.jobs_enqueued
  end

  test "supports all scope and limit" do
    second_event = Event.create!(
      title: "Second warm event",
      artist_name: "Second Artist",
      start_at: Time.zone.local(2026, 9, 1, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )
    second_event.import_event_images.create!(
      source: "eventim",
      image_type: "large",
      image_url: "https://example.com/second.jpg",
      role: "cover",
      aspect_hint: "landscape"
    )

    result = nil
    assert_enqueued_jobs 1, only: Importing::CacheImportEventImageJob do
      result = Events::Maintenance::ImportImageCacheWarmer.call(scope: "all", limit: 1)
    end

    assert_equal 1, result.images_scanned
    assert_equal 1, result.jobs_enqueued
  end

  test "all scope scans unpublished images too" do
    second_event = Event.create!(
      title: "Scope all event",
      artist_name: "Scope Artist",
      start_at: Time.zone.local(2026, 9, 2, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )
    second_event.import_event_images.create!(
      source: "eventim",
      image_type: "large",
      image_url: "https://example.com/scope-all.jpg",
      role: "cover",
      aspect_hint: "landscape"
    )

    result = nil
    assert_enqueued_jobs 2, only: Importing::CacheImportEventImageJob do
      result = Events::Maintenance::ImportImageCacheWarmer.call(scope: "all")
    end

    assert_equal 2, result.images_scanned
    assert_equal 2, result.images_eligible
  end
end
