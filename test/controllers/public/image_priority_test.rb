require "test_helper"

class Public::ImagePriorityTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    @events = [ events(:published_one) ]
    4.times do |index|
      @events << @events.first.dup.tap do |event|
        event.assign_attributes(slug: "priority-event-#{index}", source_fingerprint: "test::priority::#{index}", artist_name: "Published Artist #{index}")
        event.save!
      end
    end
    @events.each do |event|
      image = event.event_images.build(purpose: EventImage::PURPOSE_SLIDER)
      image.file.attach(create_uploaded_blob)
      image.save!
      event.update!(highlighted: true)
    end
  end

  teardown { travel_back }

  test "initial list pages prioritize both visible mobile rows and keep later cards lazy" do
    [ highlights_lane_path, search_path(q: "Published Artist") ].each do |path|
      get path
      assert_response :success
      images = css_select(".design-preview-list-card-grid .design-preview-card-image[src]")
      assert_equal 5, images.size
      images.first(4).each do |image|
        assert_equal "eager", image["loading"], path
        assert_equal "high", image["fetchpriority"], path
      end
      assert_equal "lazy", images.last["loading"], path
      assert_nil images.last["fetchpriority"], path
    end
  end

  test "subsequent list pages do not prioritize images below the initial viewport" do
    get homepage_lane_events_path(lane: "highlights", mode: "design_cards")

    assert_response :success
    assert_select ".design-preview-card-image[loading='lazy']", count: 5
    assert_select ".design-preview-card-image[fetchpriority='high']", count: 0
  end

  test "direct subpages do not preload the homepage through the logo" do
    [ highlights_lane_path, search_path(q: "Published Artist"), event_path(@events.first.slug), news_index_path ].each do |path|
      get path
      assert_response :success
      assert_select ".design-preview-logo[data-turbo-preload]", count: 0
    end
  end

  test "event detail hero is eager with high fetch priority" do
    get event_path(@events.first.slug)
    assert_response :success
    assert_select ".design-detail-preview-image-slide:not([hidden]) img[loading='eager'][fetchpriority='high']", count: 1
  end

  test "news index prioritizes the first cover and reserves image space" do
    2.times do |index|
      post = BlogPost.create!(title: "Priority News #{index}", slug: "priority-news-#{index}", teaser: "Aktuelle News", body: "Ein Beitrag", status: "published", published_at: index.hours.ago, author: users(:one))
      post.cover_image.attach(create_uploaded_blob(width: 40, height: 30))
    end
    get news_index_path
    assert_response :success
    images = css_select(".news-index-card-media img")
    assert_equal 2, images.size
    assert_equal "eager", images.first["loading"]
    assert_equal "high", images.first["fetchpriority"]
    assert_equal "lazy", images.last["loading"]
    assert_nil images.last["fetchpriority"]
    images.each do |image|
      assert image["width"].to_i.positive?
      assert image["height"].to_i.positive?
    end
  end

  test "homepage highlight video defers source assignment until eligibility" do
    get root_path
    assert_response :success
    assert_select ".homepage-highlight-video[data-video-sound-src-value][preload='none']:not([src])", count: 1
    assert_select ".homepage-highlight-video source[src]", count: 0
    assert_select ".homepage-highlight-video-card[data-video-sound-media-value='(min-width: 80rem)']", count: 1
  end
end
