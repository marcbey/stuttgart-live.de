require "test_helper"

class Events::Retention::PrunePastRawEventImportsJobTest < ActiveJob::TestCase
  test "delegates to raw import retention service" do
    captured = false
    original_call = Events::Retention::PrunePastRawEventImports.method(:call)

    Events::Retention::PrunePastRawEventImports.singleton_class.define_method(:call) do |*args, **kwargs|
      captured = true
      Events::Retention::PrunePastRawEventImports::Result.new(
        deleted_count: 0,
        deleted_by_source: {},
        skipped_count: 0,
        cutoff_at: Time.zone.parse("2026-03-15 00:00:00")
      )
    end

    Events::Retention::PrunePastRawEventImportsJob.perform_now

    assert captured
  ensure
    Events::Retention::PrunePastRawEventImports.singleton_class.define_method(:call, original_call)
  end
end
