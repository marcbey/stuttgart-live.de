require "test_helper"

class Backend::EventsHelperTest < ActionView::TestCase
  include Backend::EventsHelper

  test "event_display_status_label shows planned label for future ready_for_publish events" do
    event = events(:needs_review_one)
    event.status = "ready_for_publish"
    event.published_at = 2.hours.from_now

    assert_equal "Unpublished/Geplant", event_display_status_label(event)
    assert_equal "status-badge status-badge-ready", event_display_status_badge_class(event)
  end

  test "event_active_llm_enrichment_run returns queued or running single event run" do
    event = events(:published_one)
    ImportRun.create!(
      import_source: import_sources(:two),
      status: "queued",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: {
        "trigger_scope" => "single_event",
        "target_event_id" => event.id
      }
    )

    run = event_active_llm_enrichment_run(event)

    assert_equal "queued", run.status
  end

  test "event_active_llm_enrichment_run ignores finished and other event runs" do
    event = events(:published_one)
    ImportRun.create!(
      import_source: import_sources(:two),
      status: "succeeded",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      finished_at: Time.current,
      metadata: {
        "trigger_scope" => "single_event",
        "target_event_id" => event.id
      }
    )
    ImportRun.create!(
      import_source: import_sources(:two),
      status: "running",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: {
        "trigger_scope" => "single_event",
        "target_event_id" => events(:needs_review_one).id
      }
    )

    assert_nil event_active_llm_enrichment_run(event)
  end
end
