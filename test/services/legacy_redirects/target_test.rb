require "test_helper"

class LegacyRedirectTargetTest < ActiveSupport::TestCase
  test "resolves only published canonical public routes and fixed lanes" do
    assert_equal({ target: events(:published_one), target_path: nil }, LegacyRedirects::Target.resolve("/events/published-event"))
    assert_equal({ target: nil, target_path: "/highlights" }, LegacyRedirects::Target.resolve("/highlights"))
    assert_equal({ target: genres(:rock), target_path: nil }, LegacyRedirects::Target.resolve("/rock-alternative"))
    %w[/events/needs-review-event /events/missing /blog/old /search /design-preview /events/published-event/related /news/missing /session/new].each do |path|
      assert_nil LegacyRedirects::Target.resolve(path), path
    end
    events(:published_one).update_columns(published_at: 1.day.from_now)
    assert_nil LegacyRedirects::Target.resolve("/events/published-event")
  end

  test "resolves public static pages and live news with current slugs" do
    page = StaticPage.create!(title: "Example", body: "<p>Content</p>")
    post = BlogPost.create!(title: "Live", teaser: "Teaser", body: "<p>Content</p>", author: users(:one), status: "published", published_at: 1.hour.ago)
    assert_equal page, LegacyRedirects::Target.resolve("/example")[:target]
    assert_equal post, LegacyRedirects::Target.resolve("/news/live")[:target]
    post.update!(published_at: 1.day.from_now)
    assert_nil LegacyRedirects::Target.resolve("/news/live")
  end

  test "rejects existing records whose canonical URLs are shadowed by other public actions" do
    page = StaticPage.create!(title: "Preview page", slug: "design-preview", body: "<p>Content</p>")
    event = events(:published_one)
    event.update!(slug: "homepage_lane")
    [ [ page, "/design-preview" ], [ event, "/events/homepage_lane" ] ].each do |record, path|
      assert_nil LegacyRedirects::Target.resolve(path), path
      rule = LegacyRedirect.new(source_path: "/old-#{record.class.name}", status: "redirect", target: record)
      assert_nil LegacyRedirects::Target.path_for(rule), path
      assert_not rule.valid?, path
    end
  end

  test "blob targets require public attachment fields public owners and existing files" do
    blob = create_uploaded_blob
    rule = LegacyRedirect.new(target: blob)
    assert_nil LegacyRedirects::Target.path_for(rule)
    event = events(:published_one)
    event.promotion_banner_image.attach(blob)
    with_media_proxy(enabled: false) do
      path = LegacyRedirects::Target.path_for(rule)
      assert_match %r{\A/rails/active_storage/blobs/proxy/}, path
      assert_equal blob, LegacyRedirects::Target.resolve(path)[:target]
    end
    with_media_proxy do
      path = LegacyRedirects::Target.path_for(rule)
      assert_match %r{\A/media/}, path
      assert_equal blob, LegacyRedirects::Target.resolve(path)[:target]
    end
    event.update_columns(status: "needs_review")
    assert_nil LegacyRedirects::Target.path_for(rule)
    event.update_columns(status: "published")
    blob.service.delete(blob.key)
    assert_nil LegacyRedirects::Target.path_for(rule)
  end

  test "public event images and static page rich text are accepted" do
    image_blob = create_uploaded_blob
    image = EventImage.create!(event: events(:published_one), purpose: "slider", file: image_blob)
    assert LegacyRedirects::Target.path_for(LegacyRedirect.new(target: image_blob))
    image.event.update_columns(status: "needs_review")
    assert_nil LegacyRedirects::Target.path_for(LegacyRedirect.new(target: image_blob))

    page = StaticPage.create!(title: "Media Page", body: "<p>Content</p>")
    page_blob = create_uploaded_blob
    ActiveStorage::Attachment.create!(name: "embeds", record: page.body, blob: page_blob)
    assert LegacyRedirects::Target.path_for(LegacyRedirect.new(target: page_blob))
    page.destroy!
    assert_nil LegacyRedirects::Target.path_for(LegacyRedirect.new(target: page_blob))
  end

  test "rich text press attachments and user attachments cannot become public targets" do
    blob = create_uploaded_blob
    event = events(:published_one)
    event.press_text = ActionText::Content.new("<p>Press</p>#{blob.attachable_sgid}")
    event.save!
    ActiveStorage::Attachment.create!(name: "embeds", record: event.press_text, blob: blob)
    assert_nil LegacyRedirects::Target.path_for(LegacyRedirect.new(target: blob))
    path = Rails.application.routes.url_helpers.rails_storage_proxy_path(blob, only_path: true)
    assert_nil LegacyRedirects::Target.resolve(path)
  end
end
