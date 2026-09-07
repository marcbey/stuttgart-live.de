# frozen_string_literal: true

require "open3"
require "tempfile"

module Media
  class VideoCompressor
    FFMPEG_COMMAND = "ffmpeg"
    VIDEO_FILTER = "scale=w='min(720,iw)':h=-2:force_original_aspect_ratio=decrease,fps=30"
    CONTENT_TYPE = "video/mp4"

    def self.call(blob)
      new(blob).call
    end

    def initialize(blob)
      @blob = blob
    end

    def call
      return blob unless compressible?

      blob.open(tmpdir: Rails.root.join("tmp")) do |input_file|
        compress_file(input_file)
      end
    rescue StandardError => error
      Rails.logger.warn("Highlight video compression skipped: #{error.class}: #{error.message}")
      blob
    end

    private

    attr_reader :blob

    def compressible?
      blob.present? && blob.content_type.to_s.start_with?("video/")
    end

    def compress_file(input_file)
      Tempfile.create([ "highlight-video-", ".mp4" ], Rails.root.join("tmp"), binmode: true) do |output_file|
        output_file.close

        _, error_output, status = Open3.capture3(*ffmpeg_args(input_file.path, output_file.path))
        raise "ffmpeg failed: #{error_output.presence || status.exitstatus}" unless status.success?
        raise "ffmpeg generated an empty video" unless File.size?(output_file.path)

        create_blob(output_file.path)
      end
    end

    def ffmpeg_args(input_path, output_path)
      [
        FFMPEG_COMMAND,
        "-y",
        "-i", input_path,
        "-map", "0:v:0",
        "-map", "0:a?",
        "-vf", VIDEO_FILTER,
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "28",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        "-b:a", "96k",
        "-ac", "2",
        "-movflags", "+faststart",
        output_path
      ]
    end

    def create_blob(path)
      File.open(path, "rb") do |file|
        ActiveStorage::Blob.create_and_upload!(
          io: file,
          filename: compressed_filename,
          content_type: CONTENT_TYPE,
          identify: false
        )
      end
    end

    def compressed_filename
      "#{blob.filename.base}-web.mp4"
    end
  end
end
