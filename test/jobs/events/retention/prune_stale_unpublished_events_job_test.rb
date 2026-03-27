require "test_helper"

class Events::Retention::PruneStaleUnpublishedEventsJobTest < ActiveJob::TestCase
  test "delegates to stale unpublished event retention service" do
    captured = false
    original_call = Events::Retention::PruneStaleUnpublishedEvents.method(:call)

    Events::Retention::PruneStaleUnpublishedEvents.singleton_class.define_method(:call) do |*args, **kwargs|
      captured = true
      Events::Retention::PruneStaleUnpublishedEvents::Result.new(
        deleted_count: 0,
        deleted_by_status: {},
        cutoff_at: Time.zone.parse("2026-03-15 00:00:00")
      )
    end

    Events::Retention::PruneStaleUnpublishedEventsJob.perform_now

    assert captured
  ensure
    Events::Retention::PruneStaleUnpublishedEvents.singleton_class.define_method(:call, original_call)
  end
end
