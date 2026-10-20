module PublicImages
  class HostLock
    class Busy < StandardError; end

    def initialize(path: ENV.fetch("PUBLIC_IMAGE_LOCK_PATH") { Rails.root.join("tmp/public-image-work.lock") })
      @path = path
    end

    def synchronize
      File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
        raise Busy, "Public image work is already active" unless file.flock(File::LOCK_EX | File::LOCK_NB)

        begin
          yield
        ensure
          file.flock(File::LOCK_UN)
        end
      end
    end
  end
end
