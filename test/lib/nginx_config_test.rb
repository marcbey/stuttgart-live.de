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
end
