require "test_helper"

class Importing::ImportEventImagesSyncTest < ActiveSupport::TestCase
  test "normalizes and deduplicates candidates for import records" do
    record = eventim_import_events(:one)

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

    assert_equal true, changed

    assert_equal [
      [ "eventim", "espicture_big", "cover", "landscape", 0, "https://example.com/cover_1200x800.jpg" ],
      [ "eventim", "espicture_small", "thumb", "square", 1, "https://example.com/thumb_400x400.jpg" ]
    ], record.import_event_images.reload.ordered.pluck(:source, :image_type, :role, :aspect_hint, :position, :image_url)
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
      [ "eventim", "espicture_small", "thumb", "square", 0, "https://example.com/replacement_400x400.jpg" ]
    ], event.import_event_images.reload.ordered.pluck(:source, :image_type, :role, :aspect_hint, :position, :image_url)
  end
end
