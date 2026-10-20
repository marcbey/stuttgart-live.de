require "test_helper"

class PublicImagesRepresentationTest < ActionView::TestCase
  include ApplicationHelper

  test "rendering public paths never creates variants and falls back to original" do
    assert_no_difference "ActiveStorage::VariantRecord.count" do
      assert_equal public_media_path(portrait_image.file), optimized_event_image_source(portrait_image, size: :card_mobile)
      assert optimized_event_image_srcset(portrait_image, variant_sizes: %i[card_mobile card_desktop]).present?
    end
  end

  test "ready portrait outputs use actual pixel widths and missing output falls back" do
    variant = portrait_image.optimized_public_variant(:card_mobile).processed
    variant.image.blob.analyze
    assert_equal 192, variant.image.blob.metadata["width"]
    srcset = optimized_event_image_srcset(portrait_image, variant_sizes: %i[card_mobile])
    assert_match(/ 192w\z/, srcset)
    variant.image.blob.service.delete(variant.image.blob.key)
    assert_equal public_media_path(portrait_image.file), optimized_event_image_source(portrait_image, size: :card_mobile)
  end

  test "imported ready output is used by public source and srcset while source changes fall back" do
    image = events(:published_one).import_event_images.create!(source: "easyticket", image_type: "image_url", image_url: "https://images.example/original", role: "cover", aspect_hint: "portrait", position: 0)
    blob = portrait_image.file.blob
    blob.update!(metadata: blob.metadata.merge("public_source_fingerprint" => image.public_source_fingerprint))
    image.prepared_file.attach(blob)
    assert_equal public_media_path(blob), optimized_event_image_source(image, size: :card_mobile)
    assert_match(/ 600w\z/, optimized_event_image_srcset(image, variant_sizes: %i[card_mobile]))
    image.update!(image_url: "https://images.example/new")
    assert_equal "https://images.example/new", optimized_event_image_source(image, size: :card_mobile)
  end

  test "fully loaded public representations use ready output without SQL or processing" do
    output = portrait_image.optimized_public_variant(:card_mobile).processed.image.blob
    output.analyze
    image = EventImage.preload(file_attachment: { blob: { variant_records: { image_attachment: :blob } } }).find(portrait_image.id)
    queries = []
    callback = ->(notification) { queries << notification.payload[:sql] unless notification.payload[:name] == "SCHEMA" }

    assert_no_difference "ActiveStorage::VariantRecord.count" do
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        assert_equal public_media_path(output), optimized_event_image_source(image, size: :card_mobile)
        assert_match(/ 192w\z/, optimized_event_image_srcset(image, variant_sizes: [ :card_mobile ]))
      end
    end
    assert_empty queries
  end

  test "small sources have one candidate per intrinsic width" do
    image = EventImage.new(event: events(:needs_review_one), purpose: "slider")
    image.file.attach(io: StringIO.new(Vips::Image.black(100, 100).pngsave_buffer), filename: "small.png", content_type: "image/png")
    image.save!
    PublicImages::Preparation.new.call(image)
    candidates = optimized_event_image_srcset(image.reload, variant_sizes: %i[thumbnail card_mobile card_desktop]).split(", ")
    assert_equal 1, candidates.length
    assert_match(/ 100w\z/, candidates.first)
  end

  test "logos in public helpers never process new variants" do
    venue = venues(:lka_longhorn)
    venue.logo.attach(portrait_image.file.blob)
    assert_no_difference "ActiveStorage::VariantRecord.count" do
      assert_equal public_media_path(venue.logo), venue_logo_source(venue)
    end
  end

  test "rich text render never prepares a variant" do
    assert_no_difference "ActiveStorage::VariantRecord.count" do
      assert_equal public_media_path(portrait_image.file.blob), public_rich_text_representation_source(portrait_image.file.blob)
    end
  end

  test "banner and news public paths do not process new variants" do
    event = events(:needs_review_one)
    event.promotion_banner_image.attach(portrait_image.file.blob)
    post = BlogPost.new
    post.cover_image.attach(portrait_image.file.blob)
    assert_no_difference "ActiveStorage::VariantRecord.count" do
      assert_equal public_media_path(event.promotion_banner_image), optimized_event_promotion_banner_image_source(event, size: :banner_mobile)
      assert_equal public_media_path(post.cover_image), optimized_blog_post_image_source(post, :cover_image, size: :banner_desktop)
    end
  end

  private

  # Build within the test: Bullet starts after setup callbacks have completed.
  def portrait_image
    @portrait_image ||= begin
      image = EventImage.new(event: events(:needs_review_one), purpose: "slider")
      image.file.attach(io: StringIO.new(Vips::Image.black(600, 1200).pngsave_buffer), filename: "portrait.png", content_type: "image/png")
      image.save!
      image.file.blob.analyze
      image
    end
  end
end
