require "test_helper"

class PublicImagesHostLockTest < ActiveSupport::TestCase
  test "separate processes cannot acquire the same lock and release after exit" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "work.lock")
      PublicImages::HostLock.new(path:).synchronize do
        reader, writer = IO.pipe
        pid = fork do
          reader.close
          result = begin
            PublicImages::HostLock.new(path:).synchronize { "acquired" }
          rescue PublicImages::HostLock::Busy
            "busy"
          end
          writer.write(result)
          writer.close
          exit! 0
        end
        writer.close
        assert_equal "busy", reader.read
        Process.wait(pid)
        reader.close
      end
      assert_equal :acquired, PublicImages::HostLock.new(path:).synchronize { :acquired }
    end
  end
end
