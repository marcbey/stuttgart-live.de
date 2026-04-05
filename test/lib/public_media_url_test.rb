require "test_helper"

class PublicMediaUrlTest < ActiveSupport::TestCase
  test "builds a signed path for blobs on disk" do
    blob = create_uploaded_blob(filename: "hero image.png")
    relative_path = File.join(blob.key.first(2), blob.key[2, 2], blob.key)

    with_media_proxy do
      travel_to Time.zone.local(2026, 4, 6, 12, 0, 0) do
        expires_at = Time.current.to_i + 1.year.to_i
        path = PublicMediaUrl.path_for(blob)

        assert_equal "/media/#{expires_at}/#{PublicMediaUrl.signature_for(expires_at:, relative_path:)}/#{relative_path}--hero%20image.png", path
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

  test "returns nil when media proxy is disabled" do
    blob = create_uploaded_blob(filename: "disabled.png")

    with_media_proxy(enabled: false) do
      assert_nil PublicMediaUrl.path_for(blob)
    end
  end
end
