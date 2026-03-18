require "test_helper"

class Events::Maintenance::PurgerTest < ActiveSupport::TestCase
  FakeQueueRecord = Class.new do
    def self.transaction
      yield
    end
  end

  FakeQueueModel = Struct.new(:count) do
    def delete_all
      self.count = 0
    end
  end

  setup do
    events(:published_one).event_change_logs.create!(
      action: "updated",
      user: users(:one),
      changed_fields: { "title" => [ "Alt", "Neu" ] },
      metadata: {}
    )
    import_runs(:one).import_run_errors.create!(
      source_type: "easyticket",
      message: "Fehler",
      error_class: "RuntimeError",
      payload: {}
    )
    import_source_configs(:one).update!(
      settings: import_source_configs(:one).settings.merge(
        ImportSourceConfig::RESERVIX_CHECKPOINT_KEY => {
          "lastupdate" => "2026-03-10T12:34:56+01:00",
          "last_processed_event_id" => "rvx-123"
        }
      )
    )
    EventLlmEnrichment.create!(
      event: events(:published_one),
      source_run: import_runs(:one),
      genre: [ "Jazz" ],
      venue: events(:published_one).venue,
      artist_description: "Beschreibung",
      event_description: "Event-Beschreibung",
      venue_description: "Venue-Beschreibung",
      model: "gpt-5-mini",
      prompt_version: "v1",
      raw_response: {}
    )
  end

  test "purges event data and keeps import data by default" do
    result = Events::Maintenance::Purger.call

    assert_equal 0, Event.count
    assert_equal 0, EventLlmEnrichment.count
    assert_equal 0, EventOffer.count
    assert_equal 0, EventGenre.count
    assert_equal 0, EventChangeLog.count
    assert_equal 0, ImportEventImage.where(import_class: "Event").count
    assert_equal 1, RawEventImport.count
    assert_equal 2, ImportRun.count
    assert_equal 1, ImportRunError.count
    assert_equal :not_requested, result.solid_queue_status
    assert_empty result.import_counts
    assert_empty result.solid_queue_counts
    assert_equal 0, result.event_counts.fetch("event_llm_enrichments")
  end

  test "purges import runtime data and resets reservix checkpoints" do
    result = Events::Maintenance::Purger.call(include_imports: true, include_solid_queue: true, solid_queue_available: false)

    assert_equal 0, RawEventImport.count
    assert_equal 0, ImportRun.count
    assert_equal 0, ImportRunError.count
    assert_equal 2, ImportSource.count
    assert_equal 2, ImportSourceConfig.count
    assert_equal({}, import_source_configs(:one).reload.reservix_checkpoint)
    assert_equal :skipped, result.solid_queue_status
    assert_equal 0, result.import_counts.fetch("import_runs")
    assert_equal 0, result.import_counts.fetch("import_run_errors")
    assert_equal 0, result.import_counts.fetch("reservix_checkpoints")
    assert_empty result.solid_queue_counts
  end

  test "purges solid queue runtime tables when available" do
    fake_models = [
      [ "solid_queue_blocked_executions", FakeQueueModel.new(1) ],
      [ "solid_queue_claimed_executions", FakeQueueModel.new(1) ],
      [ "solid_queue_failed_executions", FakeQueueModel.new(1) ],
      [ "solid_queue_ready_executions", FakeQueueModel.new(1) ],
      [ "solid_queue_recurring_executions", FakeQueueModel.new(1) ],
      [ "solid_queue_scheduled_executions", FakeQueueModel.new(1) ],
      [ "solid_queue_jobs", FakeQueueModel.new(2) ],
      [ "solid_queue_pauses", FakeQueueModel.new(1) ],
      [ "solid_queue_processes", FakeQueueModel.new(1) ],
      [ "solid_queue_semaphores", FakeQueueModel.new(1) ]
    ]

    result = Events::Maintenance::Purger.call(
      include_solid_queue: true,
      solid_queue_available: true,
      solid_queue_models: fake_models,
      solid_queue_record_class: FakeQueueRecord
    )

    assert_equal :cleared, result.solid_queue_status
    assert_equal(
      {
        "solid_queue_blocked_executions" => 0,
        "solid_queue_claimed_executions" => 0,
        "solid_queue_failed_executions" => 0,
        "solid_queue_ready_executions" => 0,
        "solid_queue_recurring_executions" => 0,
        "solid_queue_scheduled_executions" => 0,
        "solid_queue_jobs" => 0,
        "solid_queue_pauses" => 0,
        "solid_queue_processes" => 0,
        "solid_queue_semaphores" => 0
      },
      result.solid_queue_counts
    )
  end
end
