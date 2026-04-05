require "test_helper"

class Importing::ImportEventImagesSyncTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
  end

  test "normalizes and deduplicates candidates for events" do
    record = Event.create!(
      title: "Import Image Event",
      artist_name: "Import Image Artist",
      start_at: Time.zone.local(2026, 6, 1, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )

    changed = nil
    assert_enqueued_jobs 2, only: Importing::CacheImportEventImageJob do
      changed = Importing::ImportEventImagesSync.call(
        owner: record,
        source: "eventim",
        candidates: [
          { "image_url" => "https://example.com/placeholder.jpg", "image_type" => "espicture_small" },
          { "image_url" => "https://example.com/cover_1200x800.jpg", "image_type" => "espicture_big" },
          { "image_url" => "https://example.com/cover_1200x800.jpg", "image_type" => "espicture_big" },
          { "image_url" => "https://example.com/thumb_400x400.jpg", "image_type" => "espicture_small" }
        ]
      )
    end

    assert_equal true, changed

    assert_equal [
      [ "eventim", "espicture_big", "cover", "landscape", 0, "https://example.com/cover_1200x800.jpg", "pending" ],
      [ "eventim", "espicture_small", "thumb", "square", 1, "https://example.com/thumb_400x400.jpg", "pending" ]
    ], record.import_event_images.reload.ordered.pluck(:source, :image_type, :role, :aspect_hint, :position, :image_url, :cache_status)
  end

  test "is idempotent for unchanged images and replaces stale event images" do
    event = events(:published_one)

    unchanged = Importing::ImportEventImagesSync.call(
      owner: event,
      candidates: [
        {
          source: "easyticket",
          image_type: "large",
          image_url: "https://example.com/published.jpg",
          role: "cover",
          aspect_hint: "landscape"
        }
      ]
    )

    assert_equal false, unchanged

    replaced = Importing::ImportEventImagesSync.call(
      owner: event,
      candidates: [
        {
          source: "eventim",
          image_type: "espicture_small",
          image_url: "https://example.com/replacement_400x400.jpg"
        }
      ]
    )

    assert_equal true, replaced
    assert_equal [
      [ "eventim", "espicture_small", "thumb", "square", 0, "https://example.com/replacement_400x400.jpg", "pending" ]
    ], event.import_event_images.reload.ordered.pluck(:source, :image_type, :role, :aspect_hint, :position, :image_url, :cache_status)
  end
end
