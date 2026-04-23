require "test_helper"

class Backend::ImportSources::RunQueueCoordinationTest < ActiveJob::TestCase
  setup do
    clear_enqueued_jobs
    @registry = Backend::ImportSources::ImporterRegistry.new
    @maintenance = Backend::ImportSources::RunMaintenance.new(registry: @registry)
    @dispatcher = Backend::ImportSources::RunDispatcher.new(registry: @registry)
    @enqueuer = Backend::ImportSources::RunEnqueuer.new(
      registry: @registry,
      maintenance: @maintenance,
      dispatcher: @dispatcher
    )
    @stopper = Backend::ImportSources::RunStopper.new(
      registry: @registry,
      dispatcher: @dispatcher
    )
    @source = import_sources(:two)
  end

  test "serial queue dispatches first run and leaves the second queued" do
    first_result = nil
    second_result = nil

    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      first_result = @enqueuer.call(
        source_type: "llm_enrichment",
        import_source: @source,
        run_metadata: {}
      )
    end

    assert_no_enqueued_jobs only: Importing::LlmEnrichment::RunJob do
      second_result = @enqueuer.call(
        source_type: "llm_enrichment",
        import_source: @source,
        run_metadata: {}
      )
    end

    assert_equal true, first_result.dispatched
    assert_equal 1, first_result.queue_position
    assert_equal "queued", first_result.run.reload.status
    assert first_result.run.metadata["job_id"].present?

    assert_equal false, second_result.dispatched
    assert_equal 2, second_result.queue_position
    assert_equal "queued", second_result.run.reload.status
    assert_nil second_result.run.metadata["job_id"]
  end

  test "canceling a queued run dispatches the next queued run" do
    first_result = nil
    second_result = nil

    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      first_result = @enqueuer.call(source_type: "llm_enrichment", import_source: @source, run_metadata: {})
    end

    assert_no_enqueued_jobs only: Importing::LlmEnrichment::RunJob do
      second_result = @enqueuer.call(source_type: "llm_enrichment", import_source: @source, run_metadata: {})
    end

    clear_enqueued_jobs

    result = nil
    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      result = @stopper.call(
        source_type: "llm_enrichment",
        import_source: @source,
        run_id: first_result.run.id
      )
    end

    assert_equal :canceled_queue, result.action
    assert_equal "canceled", first_result.run.reload.status
    assert second_result.run.reload.metadata["job_id"].present?
  end

  test "force-canceling a running single-event llm run dispatches the next queued run" do
    running_run = @source.import_runs.create!(
      status: "running",
      source_type: "llm_enrichment",
      started_at: 2.minutes.ago,
      metadata: {
        "trigger_scope" => "single_event",
        "target_event_id" => events(:published_one).id
      }
    )
    queued_run = @source.import_runs.create!(
      status: "queued",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: {}
    )

    result = nil
    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      result = @stopper.call(
        source_type: "llm_enrichment",
        import_source: @source,
        run_id: running_run.id
      )
    end

    assert_equal :forced_cancel, result.action
    assert_equal "canceled", running_run.reload.status
    assert_equal "Force-stopped single-event run", running_run.metadata["stop_release_reason"]
    assert queued_run.reload.metadata["job_id"].present?
  end

  test "claiming a queued run marks it running and stores execution start" do
    result = nil

    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      result = @enqueuer.call(source_type: "llm_enrichment", import_source: @source, run_metadata: {})
    end

    clear_enqueued_jobs

    claimed_run = @dispatcher.claim_run!(
      source_type: "llm_enrichment",
      import_source: @source,
      run_id: result.run.id
    )

    assert_equal result.run.id, claimed_run.id
    assert_equal "running", claimed_run.reload.status
    assert claimed_run.metadata["execution_started_at"].present?
  end

  test "single-event llm runs dispatch immediately while fewer than ten are active" do
    9.times do |index|
      @source.import_runs.create!(
        status: "running",
        source_type: "llm_enrichment",
        started_at: (index + 1).minutes.ago,
        metadata: {
          "trigger_scope" => "single_event",
          "target_event_id" => events(:published_one).id,
          "execution_started_at" => (index + 1).minutes.ago.iso8601
        }
      )
    end

    result = nil
    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      result = @enqueuer.call(
        source_type: "llm_enrichment",
        import_source: @source,
        run_metadata: {
          "trigger_scope" => "single_event",
          "target_event_id" => events(:needs_review_one).id
        }
      )
    end

    assert_equal true, result.dispatched
    assert_equal "queued", result.run.reload.status
    assert result.run.metadata["job_id"].present?
  end

  test "single-event llm runs queue once ten are already active" do
    10.times do |index|
      @source.import_runs.create!(
        status: "running",
        source_type: "llm_enrichment",
        started_at: (index + 1).minutes.ago,
        metadata: {
          "trigger_scope" => "single_event",
          "target_event_id" => events(:published_one).id,
          "execution_started_at" => (index + 1).minutes.ago.iso8601
        }
      )
    end

    result = nil
    assert_no_enqueued_jobs only: Importing::LlmEnrichment::RunJob do
      result = @enqueuer.call(
        source_type: "llm_enrichment",
        import_source: @source,
        run_metadata: {
          "trigger_scope" => "single_event",
          "target_event_id" => events(:needs_review_one).id
        }
      )
    end

    assert_equal false, result.dispatched
    assert_equal 1, result.queue_position
    assert_nil result.run.reload.metadata["job_id"]
  end
end
