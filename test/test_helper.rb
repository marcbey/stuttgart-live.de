ENV["RAILS_ENV"] ||= "test"
require "json"
require "fileutils"

TEST_WARNING_FILTER_MASTER_PID = Process.pid
TEST_WARNING_FILTER_COUNTS_DIR = File.expand_path("../tmp/test_warning_filter_counts", __dir__)
FileUtils.rm_rf(TEST_WARNING_FILTER_COUNTS_DIR) if Process.pid == TEST_WARNING_FILTER_MASTER_PID
FileUtils.mkdir_p(TEST_WARNING_FILTER_COUNTS_DIR)

module TestWarningFilter
  MARCEL_WARNING_PATTERN = %r{/gems/marcel-[^/]+/lib/marcel/magic\.rb:120: warning: literal string will be frozen in the future}.freeze
  CSSBUNDLING_WARNING_PATTERN = %r{/gems/cssbundling-rails-[^/]+/lib/tasks/cssbundling/build\.rake:24: warning: (already initialized constant Cssbundling::Tasks::LOCK_FILES|previous definition of LOCK_FILES was here)}.freeze
  COUNTS = Hash.new(0)

  FILTERS = {
    "marcel literal string will be frozen in the future" => MARCEL_WARNING_PATTERN,
    "cssbundling LOCK_FILES constant redefined" => CSSBUNDLING_WARNING_PATTERN
  }.freeze

  def warn(message, category: nil, **kwargs)
    text = message.to_s

    FILTERS.each do |label, pattern|
      next unless text.match?(pattern)

      COUNTS[label] += 1
      return
    end

    super
  end
end

Warning.singleton_class.prepend(TestWarningFilter)

at_exit do
  counts_path = File.join(TEST_WARNING_FILTER_COUNTS_DIR, "#{Process.pid}.json")
  File.write(counts_path, JSON.generate(TestWarningFilter::COUNTS)) unless TestWarningFilter::COUNTS.empty?
  next unless Process.pid == TEST_WARNING_FILTER_MASTER_PID

  combined_counts =
    Dir.glob(File.join(TEST_WARNING_FILTER_COUNTS_DIR, "*.json")).each_with_object(Hash.new(0)) do |path, totals|
      JSON.parse(File.read(path)).each do |label, count|
        totals[label] += count.to_i
      end
    end

  next if combined_counts.empty?

  $stderr.puts("\nSuppressed test warnings:")
  combined_counts.sort.each do |label, count|
    $stderr.puts("  #{count}x #{label}")
  end
end

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
