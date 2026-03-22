ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "zlib"
require_relative "test_helpers/session_test_helper"
require "stringio"

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
      parse_png_dimensions(binary) || parse_webp_dimensions(binary) || raise(ArgumentError, "unsupported image binary")
    end

    def image_processing_backend_available?
      case ActiveStorage.variant_processor
      when :vips
        true
      when :mini_magick
        system("which convert >/dev/null 2>&1")
      else
        false
      end
    end

    def image_binary(representation)
      return representation.image.download if representation.respond_to?(:image)
      return representation.download if representation.respond_to?(:download)

      raise ArgumentError, "unsupported image representation"
    end

    def png_upload(filename: "test.png", width: 8, height: 8, rgb: [ 0, 0, 0 ])
      Rack::Test::UploadedFile.new(
        StringIO.new(solid_png_binary(width: width, height: height, rgb: rgb)),
        "image/png",
        original_filename: filename
      )
    end

    def create_uploaded_blob(filename: "test.png", width: 8, height: 8, rgb: [ 0, 0, 0 ])
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(solid_png_binary(width: width, height: height, rgb: rgb)),
        filename: filename,
        content_type: "image/png"
      )
    end

    private

    def png_chunk(type, data)
      [ data.bytesize ].pack("N") +
        type +
        data +
        [ Zlib.crc32(type + data) ].pack("N")
    end

    def parse_png_dimensions(binary)
      return unless binary.start_with?("\x89PNG\r\n\x1A\n".b)

      [ binary[16, 4].unpack1("N"), binary[20, 4].unpack1("N") ]
    end

    def parse_webp_dimensions(binary)
      return unless binary.start_with?("RIFF") && binary[8, 4] == "WEBP"

      chunk = binary[12, 4]

      case chunk
      when "VP8 "
        width, height = binary[26, 4].unpack("v2")
        [ width & 0x3FFF, height & 0x3FFF ]
      when "VP8L"
        bits = binary[21, 4].unpack1("V")
        [ (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1 ]
      when "VP8X"
        width_minus_one = little_endian_24bit(binary.byteslice(24, 3))
        height_minus_one = little_endian_24bit(binary.byteslice(27, 3))
        [ width_minus_one + 1, height_minus_one + 1 ]
      end
    end

    def little_endian_24bit(binary)
      bytes = binary.bytes
      bytes[0] | (bytes[1] << 8) | (bytes[2] << 16)
    end
  end
end

if defined?(Bullet)
  ActiveSupport::TestCase.prepend(BulletRequestLifecycle)
end
