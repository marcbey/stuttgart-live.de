require "test_helper"

class PublicImagesBackfillTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "requires a positive bounded limit and defaults to a read-only dry run" do
    assert_raises(ArgumentError) { PublicImages::Backfill.new(limit: 0) }
    assert_raises(ArgumentError) { PublicImages::Backfill.new(limit: 101) }
    event = events(:published_one)
    event.update!(start_at: 2.days.from_now)
    event.import_event_images.create!(source: "easyticket", image_type: "image_url", image_url: "https://images.example/a", role: "cover", aspect_hint: "landscape", position: 0)
    assert_no_enqueued_jobs do
      assert_equal 1, PublicImages::Backfill.new(limit: 1, event_slugs: [ event.slug ]).call.length
    end
    assert_enqueued_jobs 1, only: EventImages::PreparePublicImagesJob do
      PublicImages::Backfill.new(limit: 1, event_ids: [ event.id ], dry_run: false).call
    end
    assert_empty PublicImages::Backfill.new(limit: 1, event_slugs: [ "missing" ]).call
    event.update!(status: "needs_review")
    assert_empty PublicImages::Backfill.new(limit: 1, event_ids: [ event.id ]).call
  end
end
