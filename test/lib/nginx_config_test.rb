require "test_helper"

class NginxConfigTest < ActiveSupport::TestCase
  test "keeps legacy expiring media urls available for cached html" do
    config = Rails.root.join("config/nginx.conf.template").read
    legacy_media_location = "location ~ ^/media/(?<media_expires>\\d+)/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)--[^/]+$"
    stable_media_location = "location ~ ^/media/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)/[^/]+$"

    legacy_index = config.index(legacy_media_location)
    stable_index = config.index(stable_media_location)

    assert legacy_index, "missing legacy media location for cached HTML"
    assert stable_index, "missing stable media location"
    assert_operator legacy_index, :<, stable_index
    assert_includes config[legacy_index...stable_index], "secure_link $media_signature,$media_expires;"
    assert_includes config[legacy_index...stable_index], 'secure_link_md5 "$secure_link_expires/${media_path}${MEDIA_PROXY_SECRET}";'
    assert_includes config[legacy_index...stable_index], "try_files /$media_path =404;"
  end

  test "serves proxied svg media with an image content type before generic media" do
    config = Rails.root.join("config/nginx.conf.template").read
    svg_media_location = "location ~ ^/media/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)/[^/]+\\.svg$"
    generic_media_location = "location ~ ^/media/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)/[^/]+$"

    svg_index = config.index(svg_media_location)
    generic_index = config.index(generic_media_location)

    assert svg_index, "missing SVG-specific media location"
    assert generic_index, "missing generic media location"
    assert_operator svg_index, :<, generic_index
    assert_includes config[svg_index...generic_index], "default_type image/svg+xml;"
    assert_includes config[svg_index...generic_index], "secure_link $media_signature;"
    assert_includes config[svg_index...generic_index], 'secure_link_md5 "${media_path}${MEDIA_PROXY_SECRET}";'
    refute_includes config[svg_index...generic_index], "media_expires"
  end

  test "serves proxied raster media with concrete image content types before generic media" do
    config = Rails.root.join("config/nginx.conf.template").read
    generic_media_location = "location ~ ^/media/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)/[^/]+$"
    generic_index = config.index(generic_media_location)

    {
      "jpg|jpeg" => "image/jpeg",
      "png" => "image/png",
      "webp" => "image/webp"
    }.each do |extension_pattern, content_type|
      media_location = "location ~ ^/media/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)/[^/]+\\.(?:#{extension_pattern})$"
      media_location = "location ~ ^/media/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)/[^/]+\\.#{extension_pattern}$" unless extension_pattern.include?("|")
      media_index = config.index(media_location)

      assert media_index, "missing #{content_type} media location"
      assert_operator media_index, :<, generic_index
      assert_includes config[media_index...generic_index], "default_type #{content_type};"
      assert_includes config[media_index...generic_index], "secure_link $media_signature;"
      assert_includes config[media_index...generic_index], 'secure_link_md5 "${media_path}${MEDIA_PROXY_SECRET}";'
      refute_includes config[media_index...generic_index], "media_expires"
    end
  end
end
