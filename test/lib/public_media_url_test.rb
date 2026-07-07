require "test_helper"

class PublicMediaUrlTest < ActiveSupport::TestCase
  test "builds a signed path for blobs on disk" do
    blob = create_uploaded_blob(filename: "hero image.png")
    relative_path = File.join(blob.key.first(2), blob.key[2, 2], blob.key)

    with_media_proxy do
      travel_to Time.zone.local(2026, 4, 6, 12, 0, 0) do
        path = PublicMediaUrl.path_for(blob)
        match = path.match(%r{\A/media/([-_A-Za-z0-9]+)/#{Regexp.escape(relative_path)}/hero%20image\.png\z})

        assert match, "expected signed media path, got #{path.inspect}"
        assert_equal stable_signature_for(relative_path), match[1]
      end
    end
  end

  test "builds different signed paths for different blobs" do
    first_blob = create_uploaded_blob(filename: "first.png")
    second_blob = create_uploaded_blob(filename: "second.png")

    with_media_proxy do
      travel_to Time.zone.local(2026, 4, 6, 12, 0, 0) do
        refute_equal PublicMediaUrl.path_for(first_blob), PublicMediaUrl.path_for(second_blob)
      end
    end
  end

  test "builds different signed paths when an image file is replaced with the same filename" do
    first_blob = create_uploaded_blob(filename: "event-image.png")
    replacement_blob = create_uploaded_blob(filename: "event-image.png")

    with_media_proxy do
      assert_not_equal PublicMediaUrl.path_for(first_blob), PublicMediaUrl.path_for(replacement_blob)
    end
  end

  test "keeps signed storage path stable when filename contains url delimiter characters" do
    blob = create_uploaded_blob(filename: "hero--image.png")
    relative_path = File.join(blob.key.first(2), blob.key[2, 2], blob.key)

    with_media_proxy do
      path = PublicMediaUrl.path_for(blob)
      match = path.match(%r{\A/media/[-_A-Za-z0-9]+/(?<media_path>.+)/hero--image\.png\z})

      assert match, "expected slash-separated signed media path, got #{path.inspect}"
      assert_equal relative_path, match[:media_path]
    end
  end

  test "keeps signed paths stable over time" do
    blob = create_uploaded_blob(filename: "stable.png")

    with_media_proxy do
      travel_to Time.zone.local(2026, 4, 6, 12, 0, 0) do
        first_path = PublicMediaUrl.path_for(blob)

        travel 30.days

        assert_equal first_path, PublicMediaUrl.path_for(blob)
      end
    end
  end

  test "builds a signed path for attached one records" do
    author = users(:one)
    blog_post = BlogPost.create!(
      title: "Attached One Proxy",
      teaser: "Teaser",
      body: "<div>Inhalt</div>",
      author: author,
      status: "published",
      published_at: 1.hour.ago,
      published_by: author
    )
    blog_post.promotion_banner_image.attach(
      io: StringIO.new(solid_png_binary(width: 1200, height: 675)),
      filename: "attached-one.png",
      content_type: "image/png"
    )

    with_media_proxy do
      travel_to Time.zone.local(2026, 4, 6, 12, 0, 0) do
        assert_equal PublicMediaUrl.path_for(blog_post.promotion_banner_image.blob),
                     PublicMediaUrl.path_for(blog_post.promotion_banner_image)
      end
    end
  end

  test "returns nil when media proxy is disabled" do
    blob = create_uploaded_blob(filename: "disabled.png")

    with_media_proxy(enabled: false) do
      assert_nil PublicMediaUrl.path_for(blob)
    end
  end

  private

  def stable_signature_for(relative_path)
    Base64.strict_encode64(OpenSSL::Digest::MD5.digest("#{relative_path}test-media-secret")).tr("+/", "-_").delete("=")
  end
end
