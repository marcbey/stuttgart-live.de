require "test_helper"

class NginxConfigTest < ActiveSupport::TestCase
  test "serves proxied svg media with an image content type before generic media" do
    config = Rails.root.join("config/nginx.conf.template").read
    svg_media_location = "location ~ ^/media/(?<media_expires>\\d+)/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)--[^/]+\\.svg$"
    generic_media_location = "location ~ ^/media/(?<media_expires>\\d+)/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)--[^/]+$"

    svg_index = config.index(svg_media_location)
    generic_index = config.index(generic_media_location)

    assert svg_index, "missing SVG-specific media location"
    assert generic_index, "missing generic media location"
    assert_operator svg_index, :<, generic_index
    assert_includes config[svg_index...generic_index], "default_type image/svg+xml;"
  end

  test "serves proxied raster media with concrete image content types before generic media" do
    config = Rails.root.join("config/nginx.conf.template").read
    generic_media_location = "location ~ ^/media/(?<media_expires>\\d+)/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)--[^/]+$"
    generic_index = config.index(generic_media_location)

    {
      "jpg|jpeg" => "image/jpeg",
      "png" => "image/png",
      "webp" => "image/webp"
    }.each do |extension_pattern, content_type|
      media_location = "location ~ ^/media/(?<media_expires>\\d+)/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)--[^/]+\\.(?:#{extension_pattern})$"
      media_location = "location ~ ^/media/(?<media_expires>\\d+)/(?<media_signature>[-_A-Za-z0-9]+)/(?<media_path>.+)--[^/]+\\.#{extension_pattern}$" unless extension_pattern.include?("|")
      media_index = config.index(media_location)

      assert media_index, "missing #{content_type} media location"
      assert_operator media_index, :<, generic_index
      assert_includes config[media_index...generic_index], "default_type #{content_type};"
    end
  end
end
