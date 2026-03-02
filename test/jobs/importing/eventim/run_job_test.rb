require "test_helper"

class Importing::Eventim::RunJobTest < ActiveJob::TestCase
  test "uses eventim queue" do
    assert_equal "imports_eventim", Importing::Eventim::RunJob.queue_name
  end
end
