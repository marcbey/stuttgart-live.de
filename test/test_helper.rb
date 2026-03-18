ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "vips"
require "zlib"
require_relative "test_helpers/session_test_helper"

if defined?(Bullet)
  module BulletRequestLifecycle
    def before_setup
      super
      Bullet.start_request if bullet_enabled?
    end

    def after_teardown
      if bullet_enabled?
        Bullet.perform_out_of_channel_notifications if Bullet.notification?
        Bullet.end_request
      end

      super
    end

    private

    def bullet_enabled?
      Bullet.respond_to?(:enable?) ? Bullet.enable? : Bullet.enable
    end
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    def solid_png_binary(width:, height:, rgb: [ 0, 0, 0 ])
      signature = "\x89PNG\r\n\x1A\n".b
      ihdr = [ width, height, 8, 2, 0, 0, 0 ].pack("NNC5")
      pixel = rgb.pack("C3")
      row = ("\x00".b + (pixel * width)).b
      image_data = row * height
      idat = Zlib::Deflate.deflate(image_data, Zlib::BEST_COMPRESSION)

      signature +
        png_chunk("IHDR", ihdr) +
        png_chunk("IDAT", idat) +
        png_chunk("IEND", +"")
    end

    def image_dimensions(binary)
      image = Vips::Image.new_from_buffer(binary, "")
      [ image.width, image.height ]
    end

    private

    def png_chunk(type, data)
      [ data.bytesize ].pack("N") +
        type +
        data +
        [ Zlib.crc32(type + data) ].pack("N")
    end
  end
end

if defined?(Bullet)
  ActiveSupport::TestCase.prepend(BulletRequestLifecycle)
end
