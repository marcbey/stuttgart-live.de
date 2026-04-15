require "test_helper"

class Meta::CheckConnectionHealthJobTest < ActiveJob::TestCase
  test "runs the connection health check" do
    original_health_check = Meta::ConnectionHealthCheck
    fake_health_check_class = Class.new do
      cattr_accessor :calls, default: 0

      def call(connection: nil, refresh: true)
        self.class.calls += 1
      end
    end

    Meta.send(:remove_const, :ConnectionHealthCheck)
    Meta.const_set(:ConnectionHealthCheck, fake_health_check_class)

    Meta::CheckConnectionHealthJob.perform_now

    assert_equal 1, fake_health_check_class.calls
  ensure
    Meta.send(:remove_const, :ConnectionHealthCheck)
    Meta.const_set(:ConnectionHealthCheck, original_health_check)
  end
end
