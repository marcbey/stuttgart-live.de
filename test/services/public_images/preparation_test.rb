require "test_helper"

class PublicImagesPreparationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @event = events(:published_one)
    @event.update!(start_at: 2.days.from_now)
    @binary = Vips::Image.black(1600, 900).pngsave_buffer
  end

  test "new and replaced local images enqueue preparation without processing inline" do
    image = EventImage.new(event: @event, purpose: "slider")
    image.file.attach(io: StringIO.new(@binary), filename: "source.png", content_type: "image/png")
    assert_enqueued_with(job: EventImages::PreparePublicImagesJob) { image.save! }
    assert_empty image.file.blob.variant_records
    EventImages::PreparePublicImagesJob.perform_now(image)
    output = PublicImages::Representation.ready(image.file, size: :card_mobile)
    assert_equal "image/webp", output.content_type
    assert_equal 384, output.metadata["width"]
    assert_operator output.byte_size, :<, image.file.blob.byte_size
    assert_enqueued_with(job: EventImages::PreparePublicImagesJob) do
      image.file.attach(io: StringIO.new(@binary), filename: "replacement.png", content_type: "image/png")
    end
  end

  test "multiple saves in one transaction still prepare a changed attachment" do
    image = EventImage.new(event: @event, purpose: "slider")
    assert_enqueued_with(job: EventImages::PreparePublicImagesJob) do
      EventImage.transaction do
        image.file.attach(io: StringIO.new(@binary), filename: "source.png", content_type: "image/png")
        image.save!
        image.update!(alt_text: "Updated before commit")
      end
    end
  end

  test "banner and news uploads enqueue public preparation without inline variants" do
    post = BlogPost.create!(title: "Prepared news", teaser: "News", body: "Text", author: users(:one), status: "draft")
    [ [ @event, :promotion_banner_image ], [ post, :cover_image ] ].each do |record, slot|
      assert_enqueued_with(job: EventImages::PreparePublicImagesJob) do
        record.public_send(slot).attach(io: StringIO.new(@binary), filename: "upload.png", content_type: "image/png")
      end
      assert_empty record.public_send(slot).blob.variant_records
    end
  end

  test "an invalid first slot does not prevent preparing a later valid banner" do
    post = BlogPost.create!(title: "Invalid cover", teaser: "News", body: "Text", author: users(:one), status: "draft")
    [ [ post, :cover_image, :promotion_banner_image ], [ @event, :promotion_banner_image, :promotion_banner_landscape_image ] ].each do |record, invalid_slot, valid_slot|
      record.public_send(invalid_slot).attach(io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"/>'), filename: "unsupported.svg", content_type: "image/svg+xml")
      record.public_send(valid_slot).attach(io: StringIO.new(@binary), filename: "banner.png", content_type: "image/png")
      EventImages::PreparePublicImagesJob.perform_now(record)
      output = PublicImages::Representation.ready(record.public_send(valid_slot), size: :card_mobile)
      assert_equal "image/webp", output.content_type
      assert_equal 384, output.metadata["width"]
      assert_empty record.public_send(invalid_slot).blob.variant_records
    end
  end

  test "missing source files still propagate for job retry" do
    @event.promotion_banner_image.attach(io: StringIO.new(@binary), filename: "missing.png", content_type: "image/png")
    blob = @event.promotion_banner_image.blob
    blob.service.delete(blob.key)
    assert_raises(ActiveStorage::FileNotFoundError) { PublicImages::Preparation.new.call(@event) }
  end

  test "imports retain remote fallback until ready and do not redownload unchanged source" do
    image = imported_image
    assert_nil image.public_file
    calls = 0
    fetcher = Object.new
    fetcher.define_singleton_method(:call) { |_| calls += 1; GuardedHttpFetcher::Response.new(url: "https://images.example/a", status: 200, content_type: "image/png", body: @body) }
    fetcher.instance_variable_set(:@body, @binary)
    service = PublicImages::Preparation.new(fetcher:)
    service.call(image)
    assert_equal 384, PublicImages::Representation.ready(image.public_file, size: :card_mobile).metadata["width"]
    service.call(image)
    assert_equal 1, calls
    image.update!(image_url: "https://images.example/replacement")
    assert_nil image.public_file
  end

  test "in flight source replacement cannot publish stale downloaded output" do
    image = imported_image
    binary = @binary
    fetcher = Object.new
    fetcher.define_singleton_method(:call) do |_|
      ImportEventImage.find(image.id).update!(image_url: "https://images.example/new")
      GuardedHttpFetcher::Response.new(url: "https://images.example/a", status: 200, content_type: "image/png", body: binary)
    end
    PublicImages::Preparation.new(fetcher:).call(image)
    assert_not image.reload.prepared_file.attached?
  end

  test "only relevant Event owners automatically enqueue imports including publication" do
    draft = events(:needs_review_one)
    draft.update!(start_at: 2.days.from_now)
    assert_no_enqueued_jobs(only: EventImages::PreparePublicImagesJob) { imported_image(owner: draft) }
    assert_enqueued_with(job: EventImages::PreparePublicImagesJob) { draft.update!(status: "published", published_at: Time.current) }
    assert_no_enqueued_jobs(only: EventImages::PreparePublicImagesJob) { draft.update!(title: "Unchanged images") }
  end

  test "unsupported vector input is rejected before any raster work" do
    image = imported_image
    fetcher = Object.new
    fetcher.define_singleton_method(:call) { |_| GuardedHttpFetcher::Response.new(url: "https://images.example/a", status: 200, content_type: "image/svg+xml", body: '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"/>') }
    assert_raises(PublicImages::Preparation::InvalidImage) { PublicImages::Preparation.new(fetcher:).call(image) }
    assert_not image.reload.prepared_file.attached?
  end

  test "rejects oversized pixel dimensions before variant processing" do
    image = imported_image
    binary = Vips::Image.black(10000, 10000).pngsave_buffer
    fetcher = Object.new
    fetcher.define_singleton_method(:call) { |_| GuardedHttpFetcher::Response.new(url: "https://images.example/a", status: 200, content_type: "image/png", body: binary) }
    assert_raises(PublicImages::Preparation::InvalidImage) { PublicImages::Preparation.new(fetcher:).call(image) }
    assert_not image.reload.prepared_file.attached?
  end

  private

  def imported_image(owner: @event)
    owner.import_event_images.create!(source: "easyticket", image_type: "image_url", image_url: "https://images.example/a", role: "cover", aspect_hint: "landscape", position: 0)
  end
end
