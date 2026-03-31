require "test_helper"

class Events::Publication::PublishScheduledEventsJobTest < ActiveJob::TestCase
  test "delegates to scheduled publication service" do
    captured = false
    original_call = Events::Publication::PublishScheduledEvents.method(:call)

    Events::Publication::PublishScheduledEvents.singleton_class.define_method(:call) do |*args, **kwargs|
      captured = true
      Events::Publication::PublishScheduledEvents::Result.new(
        processed_count: 0,
        published_count: 0,
        skipped_count: 0
      )
    end

    Events::Publication::PublishScheduledEventsJob.perform_now

    assert captured
  ensure
    Events::Publication::PublishScheduledEvents.singleton_class.define_method(:call, original_call)
  end
end
