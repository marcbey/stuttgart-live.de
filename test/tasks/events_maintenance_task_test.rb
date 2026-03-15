require "test_helper"
require "rake"

class EventsMaintenanceTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("events:maintenance:purge_all_with_imports")
    Rake::Task["events:maintenance:purge_all_with_imports"].reenable
  end

  test "purge_all_with_imports delegates to the full purger mode" do
    captured_kwargs = nil
    result = Events::Maintenance::Purger::Result.new(
      event_counts: { "events" => 0 },
      import_counts: { "import_runs" => 0 },
      solid_queue_counts: { "solid_queue_jobs" => 0 },
      solid_queue_status: :cleared
    )

    original_call = Events::Maintenance::Purger.method(:call)

    Events::Maintenance::Purger.singleton_class.define_method(:call) do |**kwargs|
      captured_kwargs = kwargs
      result
    end

    output = capture_io do
      Rake::Task["events:maintenance:purge_all_with_imports"].invoke
    end.first

    assert_equal({ include_imports: true, include_solid_queue: true }, captured_kwargs)
    assert_includes output, "Event-, Import- und Queue-Daten gelöscht."
    assert_includes output, "events=0"
    assert_includes output, "import_runs=0"
    assert_includes output, "solid_queue_jobs=0"
  ensure
    Events::Maintenance::Purger.singleton_class.define_method(:call, original_call)
  end
end
