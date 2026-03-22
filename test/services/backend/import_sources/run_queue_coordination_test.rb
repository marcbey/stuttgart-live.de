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
end
