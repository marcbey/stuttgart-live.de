require "test_helper"
require "rake"

class EventsMaintenanceTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("events:maintenance:purge_all_with_imports")
    Rake::Task["events:maintenance:purge_all_with_imports"].reenable
    Rake::Task["events:maintenance:reset_llm_enrichment"].reenable
    Rake::Task["events:maintenance:reset_published_at"].reenable
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

  test "reset_llm_enrichment delegates to the llm resetter" do
    captured_kwargs = nil
    result = Events::Maintenance::LlmResetter::Result.new(
      event_counts: { "event_llm_enrichments" => 0 },
      import_counts: { "llm_import_runs" => 0, "llm_import_run_errors" => 0 },
      queue_counts: { "solid_queue_jobs" => 0 },
      queue_status: :cleared
    )

    original_call = Events::Maintenance::LlmResetter.method(:call)

    Events::Maintenance::LlmResetter.singleton_class.define_method(:call) do |**kwargs|
      captured_kwargs = kwargs
      result
    end

    output = capture_io do
      Rake::Task["events:maintenance:reset_llm_enrichment"].invoke
    end.first

    assert_equal({}, captured_kwargs)
    assert_includes output, "LLM-Enrichment-Daten zurückgesetzt."
    assert_includes output, "event_llm_enrichments=0"
    assert_includes output, "llm_import_runs=0"
    assert_includes output, "solid_queue_jobs=0"
  ensure
    Events::Maintenance::LlmResetter.singleton_class.define_method(:call, original_call)
  end

  test "reset_published_at clears publication dates for all events" do
    published_event = Event.create!(
      slug: "maintenance-published-at-published",
      source_fingerprint: "test::maintenance::published",
      title: "Maintenance Published",
      artist_name: "Maintenance Artist Published",
      start_at: 10.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago.change(usec: 0),
      source_snapshot: {}
    )
    review_event = Event.create!(
      slug: "maintenance-published-at-review",
      source_fingerprint: "test::maintenance::review",
      title: "Maintenance Review",
      artist_name: "Maintenance Artist Review",
      start_at: 11.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review",
      published_at: 2.days.from_now.change(usec: 0),
      source_snapshot: {}
    )
    expected_updated_count = Event.where.not(published_at: nil).count

    output = capture_io do
      Rake::Task["events:maintenance:reset_published_at"].invoke
    end.first

    assert_nil published_event.reload.published_at
    assert_nil review_event.reload.published_at
    assert_includes output, "Event-Veröffentlichungsdaten zurückgesetzt."
    assert_includes output, "events_updated=#{expected_updated_count}"
  end
end
