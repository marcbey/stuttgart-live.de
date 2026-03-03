require "test_helper"

class Importing::RetryPolicyTest < ActiveSupport::TestCase
  test "uses configured retry delays" do
    assert_equal [ 30.seconds, 1.minute, 5.minutes ], Importing::RetryPolicy::RETRY_DELAYS
    assert_equal 4, Importing::RetryPolicy::RETRY_ATTEMPTS
  end

  test "resolves delay by execution count" do
    assert_equal 30.seconds, Importing::RetryPolicy.delay_for(1)
    assert_equal 1.minute, Importing::RetryPolicy.delay_for(2)
    assert_equal 5.minutes, Importing::RetryPolicy.delay_for(3)
  end
end
