require "test_helper"

class PublicImageRenderingTest < ActionDispatch::IntegrationTest
  test "event detail HTML uses source while variants pending and distinguishes hero and related slots" do
    event = events(:published_one)
    event.update!(start_at: 2.days.from_now)
    image = event.event_images.new(purpose: "detail_hero")
    image.file.attach(io: StringIO.new(Vips::Image.black(1600, 900).pngsave_buffer), filename: "pending.png", content_type: "image/png")
    image.save!
    assert_no_difference "ActiveStorage::VariantRecord.count" do
      get event_url(event.slug)
      assert_response :success
    end
    document = Nokogiri::HTML(response.body)
    hero = document.at_css(".design-detail-preview-image-frame img")
    assert hero
    assert_match(/blobs\/proxy/, hero["src"])
    assert_includes hero["sizes"].to_s, "46rem"
  end
end
