require "test_helper"

class Backend::ImportSourcesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as(users(:one))
    @source = import_sources(:one)
    @eventim_source = import_sources(:two)
    @reservix_source = ImportSource.ensure_reservix_source!
  end

  test "should get index" do
    get backend_import_sources_url
    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Importer"
    assert_select ".app-nav-links .app-nav-link", text: "Redaktion"
  end

  test "index highlights import merge button when merge sync is needed" do
    get backend_import_sources_url

    assert_response :success
    assert_includes response.body, "Import-Merge synchronisieren"
    assert_includes response.body, "button-attention"
  end

  test "index does not highlight import merge button when latest merge is newer than imports" do
    ImportRun.create!(
      import_source: @source,
      source_type: "merge",
      status: "succeeded",
      started_at: Time.zone.parse("2026-03-03 12:00:00"),
      finished_at: Time.zone.parse("2026-03-03 12:05:00")
    )

    get backend_import_sources_url

    assert_response :success
    assert_includes response.body, "Import-Merge synchronisieren"
    assert_not_includes response.body, "button-attention"
  end

  test "should get index as json with recent runs" do
    get backend_import_sources_url(format: :json)
    assert_response :success

    payload = JSON.parse(response.body)
    assert payload["runs"].is_a?(Array)
    assert payload["runs"].any?
    assert payload["runs"].first.key?("fetched_count")
    assert payload["runs"].first.key?("upserted_count")
    assert payload["runs"].first.key?("source_type")
    assert payload["runs"].first.key?("status_label")
    assert payload["runs"].map { |run| run["source_type"] }.include?("eventim")
  end

  test "should include merge runs as stoppable jobs" do
    merge_run = @source.import_runs.create!(
      status: "running",
      source_type: "merge",
      started_at: 1.minute.ago
    )

    get backend_import_sources_url(format: :json)
    assert_response :success

    payload = JSON.parse(response.body)
    run_payload = payload.fetch("runs").find { |run| run["id"] == merge_run.id }

    assert run_payload.present?
    assert_equal "merge", run_payload["source_type"]
    assert_equal true, run_payload["can_stop"]
    assert_includes run_payload["stop_url"], "stop_merge_run"
  end

  test "should render stop action for running merge jobs" do
    merge_run = @source.import_runs.create!(
      status: "running",
      source_type: "merge",
      started_at: 1.minute.ago,
      metadata: {}
    )

    get backend_import_sources_url
    assert_response :success

    assert_select "tr[data-run-id='#{merge_run.id}'] td:last-child a", text: "Details"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:last-child form button", text: "Stoppen"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:last-child", text: /Stop angefordert/, count: 0
  end

  test "should request stop for a running merge run" do
    run = @source.import_runs.create!(
      status: "running",
      source_type: "merge",
      started_at: 1.minute.ago,
      metadata: {}
    )

    post stop_merge_run_backend_import_sources_url(run_id: run.id)

    assert_redirected_to backend_import_sources_url
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "running", run.status
  end

  test "should render stopping status instead of stop requested text" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: {
        "stop_requested" => true,
        "stop_requested_at" => 10.seconds.ago.iso8601
      }
    )

    get backend_import_sources_url
    assert_response :success

    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(2)", text: "stopping"
    assert_select "tr[data-run-id='#{run.id}'] td:last-child", text: /Stop angefordert/, count: 0
  end

  test "should show merge raw imports groups and similarity duplicates in recent runs table" do
    merge_run = @source.import_runs.create!(
      status: "succeeded",
      source_type: "merge",
      started_at: 1.minute.ago,
      finished_at: Time.current,
      fetched_count: 5,
      imported_count: 3,
      upserted_count: 999,
      metadata: {
        "import_records_count" => 5,
        "groups_count" => 3,
        "events_created_count" => 1,
        "events_updated_count" => 2,
        "duplicate_matches_count" => 1,
        "offers_upserted_count" => 999
      }
    )

    get backend_import_sources_url
    assert_response :success

    assert_select "h3", text: "Merge Importer Jobs"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(3)", text: "5"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(4)", text: "3"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(5)", text: "1"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(6)", text: "2"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(7)", text: "1"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(8)", text: "2"
  end

  test "should show source importer runs with raw imports and no merge-only metrics in recent runs table" do
    run = @source.import_runs.create!(
      status: "succeeded",
      source_type: "easyticket",
      started_at: 1.minute.ago,
      finished_at: Time.current,
      upserted_count: 7
    )

    get backend_import_sources_url
    assert_response :success

    assert_select "h3", text: "Raw Importer"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(4)", text: "7"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(5)", text: "0"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(6)", text: "7"
  end

  test "should show llm enrichment runs in dedicated llm jobs table" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      fetched_count: 120,
      filtered_count: 15,
      imported_count: 40,
      failed_count: 2,
      metadata: {
        "batches_count" => 5
      }
    )

    get backend_import_sources_url
    assert_response :success

    assert_select "h3", text: "LLM Jobs"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(3)", text: "120"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(4)", text: "15"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(5)", text: "40"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(6)", text: "5"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(7)", text: "2"
  end

  test "should show import run detail page with errors" do
    run = @source.import_runs.create!(
      status: "failed",
      source_type: "easyticket",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      error_message: "Run failed",
      metadata: {
        "job_retries_used" => 2,
        "max_retries" => 3,
        "filtered_out_cities" => [ "Berlin", "Hamburg" ]
      }
    )
    run.import_run_errors.create!(
      source_type: "easyticket",
      external_event_id: "evt-123",
      error_class: "Net::ReadTimeout",
      message: "timeout",
      payload: { "event_id" => "evt-123" }
    )

    get backend_import_run_url(run)
    assert_response :success
    assert_includes response.body, "Importer Job ##{run.id}"
    assert_includes response.body, "Net::ReadTimeout"
    assert_includes response.body, "evt-123"
    assert_includes response.body, "timeout"
    assert_includes response.body, "2 / 3"
    assert_includes response.body, "Aussortierte Städte"
    assert_includes response.body, "Berlin"
    assert_includes response.body, "Hamburg"
  end

  test "should limit recent runs json to configured size" do
    15.times do |index|
      @source.import_runs.create!(
        status: "succeeded",
        source_type: "easyticket",
        started_at: (index + 1).minutes.ago
      )
    end

    get backend_import_sources_url(format: :json)
    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal Backend::ImportRunsBroadcaster::RECENT_RUNS_LIMIT, payload["runs"].size
  end

  test "should get edit" do
    get edit_backend_import_source_url(@source)
    assert_response :success
  end

  test "should update source" do
    original_name = @source.name

    patch backend_import_source_url(@source), params: {
      import_source: {
        active: "1",
        location_whitelist_text: "Stuttgart\nEsslingen am Neckar"
      }
    }
    assert_redirected_to backend_import_sources_url
    assert_equal original_name, @source.reload.name
  end

  test "should enqueue merge sync from import sources page" do
    assert_enqueued_jobs 1, only: Merging::SyncImportedEventsJob do
      post sync_imported_events_backend_import_sources_url
    end

    assert_redirected_to backend_import_sources_url
    follow_redirect!
    assert_includes response.body, "Merge-Sync wurde gestartet."
  end

  test "should render llm enrichment button on index" do
    get backend_import_sources_url

    assert_response :success
    assert_includes response.body, "LLM-Enrichment starten"
    assert_includes response.body, "Prompt konfigurieren"
    assert_select "a[href='#{edit_backend_settings_path(anchor: "llm-enrichment-prompt")}']", text: "Prompt konfigurieren"
  end

  test "should enqueue llm enrichment run from import sources page" do
    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      post run_llm_enrichment_backend_import_sources_url
    end

    run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last
    assert_equal "running", run.status

    assert_redirected_to backend_import_sources_url
    follow_redirect!
    assert_includes response.body, "LLM-Enrichment wurde gestartet."
  end

  test "should not enqueue llm enrichment run when another llm run is active" do
    ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    assert_no_enqueued_jobs only: Importing::LlmEnrichment::RunJob do
      post run_llm_enrichment_backend_import_sources_url
    end

    assert_redirected_to backend_import_sources_url
    follow_redirect!
    assert_includes response.body, "LLM-Enrichment-Lauf läuft bereits"
  end

  test "should request stop for a running llm enrichment run" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_llm_enrichment_run_backend_import_sources_url(run_id: run.id)

    assert_redirected_to backend_import_sources_url
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    follow_redirect!
    assert_includes response.body, "Stop für LLM-Enrichment"
  end

  test "should render stop action for running llm enrichment jobs" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: {}
    )

    get backend_import_sources_url
    assert_response :success

    assert_select "tr[data-run-id='#{run.id}'] td:last-child form button", text: "Stoppen"
  end

  test "should include llm enrichment runs in recent runs json" do
    llm_run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: {}
    )

    get backend_import_sources_url(format: :json)
    assert_response :success

    payload = JSON.parse(response.body)
    run_payload = payload.fetch("runs").find { |run| run["id"] == llm_run.id }

    assert run_payload.present?
    assert_equal "llm_enrichment", run_payload["source_type"]
    assert_equal true, run_payload["can_stop"]
    assert_includes run_payload["stop_url"], "stop_llm_enrichment_run"
  end

  test "should enqueue easyticket run" do
    assert_enqueued_jobs 1 do
      post run_easyticket_backend_import_source_url(@source)
    end
    assert_redirected_to backend_import_sources_url
    follow_redirect!
    assert_not_includes response.body, "Easyticket-Import wurde gestartet."
    assert_equal "running", @source.import_runs.order(:created_at).last.status
  end

  test "should respond with turbo stream when enqueueing easyticket run" do
    assert_enqueued_jobs 1 do
      post run_easyticket_backend_import_source_url(@source), as: :turbo_stream
    end

    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes response.body, "target=\"flash-messages\""
    assert_includes response.body, "target=\"import-runs-table\""
  end

  test "should not enqueue easyticket run when another run is already active" do
    existing_run = @source.import_runs.create!(
      status: "running",
      source_type: "easyticket",
      started_at: 10.minutes.ago
    )

    assert_no_enqueued_jobs do
      post run_easyticket_backend_import_source_url(@source)
    end

    assert_redirected_to backend_import_sources_url
    assert_equal existing_run.id, @source.import_runs.order(:created_at).last.id
  end

  test "should enqueue when only stale run exists" do
    stale_run = @source.import_runs.create!(
      status: "running",
      source_type: "easyticket",
      started_at: (Importing::Easyticket::Importer::RUN_STALE_AFTER + 5.minutes).ago
    )

    assert_enqueued_jobs 1 do
      post run_easyticket_backend_import_source_url(@source)
    end

    assert_redirected_to backend_import_sources_url
    assert_equal "failed", stale_run.reload.status
    assert stale_run.finished_at.present?
  end

  test "should enqueue when stop requested run is stale by heartbeat" do
    stale_stopped_run = @source.import_runs.create!(
      status: "running",
      source_type: "easyticket",
      started_at: 5.minutes.ago,
      metadata: {
        "execution_started_at" => 5.minutes.ago.iso8601,
        "stop_requested" => true,
        "stop_requested_at" => 4.minutes.ago.iso8601
      }
    )
    stale_stopped_run.update_columns(updated_at: (Importing::Easyticket::Importer::RUN_HEARTBEAT_STALE_AFTER + 10.seconds).ago)

    assert_enqueued_jobs 1 do
      post run_easyticket_backend_import_source_url(@source)
    end

    assert_redirected_to backend_import_sources_url
    assert_equal "canceled", stale_stopped_run.reload.status
    assert stale_stopped_run.finished_at.present?
  end

  test "should request stop for a running easyticket run" do
    run = @source.import_runs.create!(
      status: "running",
      source_type: "easyticket",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_easyticket_run_backend_import_source_url(@source), params: { run_id: run.id }

    assert_redirected_to backend_import_sources_url
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "canceled", run.status
    assert run.finished_at.present?
  end

  test "should not request stop when no running run exists" do
    post stop_easyticket_run_backend_import_source_url(@source), params: { run_id: 999_999 }

    assert_redirected_to backend_import_sources_url
  end

  test "should enqueue eventim run" do
    assert_enqueued_jobs 1 do
      post run_eventim_backend_import_source_url(@eventim_source)
    end

    assert_redirected_to backend_import_sources_url
    follow_redirect!
    assert_not_includes response.body, "Eventim-Import wurde gestartet."
    assert_equal "running", @eventim_source.import_runs.order(:created_at).last.status
  end

  test "should list running runs from different importers at the same time" do
    assert_enqueued_jobs 1 do
      post run_reservix_backend_import_source_url(@reservix_source)
    end
    assert_enqueued_jobs 1 do
      post run_eventim_backend_import_source_url(@eventim_source)
    end

    get backend_import_sources_url(format: :json)
    assert_response :success

    payload = JSON.parse(response.body)
    source_types = payload.fetch("runs").map { |run| run["source_type"] }

    assert_includes source_types, "reservix"
    assert_includes source_types, "eventim"
    assert_equal "running", @reservix_source.import_runs.order(:created_at).last.status
    assert_equal "running", @eventim_source.import_runs.order(:created_at).last.status
  end

  test "should not enqueue eventim run when another run is already active" do
    existing_run = @eventim_source.import_runs.create!(
      status: "running",
      source_type: "eventim",
      started_at: 10.minutes.ago
    )

    assert_no_enqueued_jobs do
      post run_eventim_backend_import_source_url(@eventim_source)
    end

    assert_redirected_to backend_import_sources_url
    assert_equal existing_run.id, @eventim_source.import_runs.order(:created_at).last.id
  end

  test "should request stop for a running eventim run" do
    run = @eventim_source.import_runs.create!(
      status: "running",
      source_type: "eventim",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_eventim_run_backend_import_source_url(@eventim_source), params: { run_id: run.id }

    assert_redirected_to backend_import_sources_url
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "canceled", run.status
    assert run.finished_at.present?
  end

  test "should request stop for a running reservix run" do
    run = @reservix_source.import_runs.create!(
      status: "running",
      source_type: "reservix",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_reservix_run_backend_import_source_url(@reservix_source), params: { run_id: run.id }

    assert_redirected_to backend_import_sources_url
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "canceled", run.status
    assert run.finished_at.present?
  end
end
