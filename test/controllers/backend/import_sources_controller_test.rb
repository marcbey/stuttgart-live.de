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
    assert_select ".app-nav-links .app-nav-link-active", text: "Queue"
    assert_select ".app-nav-links .app-nav-link", text: "Events"
    assert_select ".import-sources-runs-section.backend-section", count: 1
    assert_select "#import-runs-live-shell.backend-tabs", count: 1
    assert_select "[data-controller='settings-tabs']", count: 1
    assert_select "#import-runs-tabs [role='tab']", count: 4
    assert_select "#import-runs-tab-raw-importer[aria-selected='true']", count: 1
    assert_match(/Events.*News.*Präsentatoren.*Venues.*Queue.*Passwort.*Logout/m, response.body)
  end

  test "should activate requested importer tab on index" do
    get backend_import_sources_url(section: :llm_enrichment)

    assert_response :success
    assert_select "#import-runs-tab-llm-enrichment[aria-selected='true']", count: 1
    assert_select "#import-runs-panel-llm-enrichment", count: 1
    assert_select "#import-runs-panel-raw-importer[hidden]", count: 1
  end

  test "should render live indicator for running tab" do
    ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: {}
    )

    get backend_import_sources_url

    assert_response :success
    assert_select "#import-runs-tab-llm-enrichment .import-runs-tab-indicator-running", text: "1"
  end

  test "index highlights import merge button when merge sync is needed" do
    get backend_import_sources_url

    assert_response :success
    assert_includes response.body, "Import-Merge starten"
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
    assert_includes response.body, "Import-Merge starten"
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
    assert_select "#import-runs-tab-merge-importer .import-runs-tab-indicator-running", text: "1"
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

  test "should respond with turbo stream when stopping a running merge run" do
    run = @source.import_runs.create!(
      status: "running",
      source_type: "merge",
      started_at: 1.minute.ago,
      metadata: {}
    )

    post stop_merge_run_backend_import_sources_url(run_id: run.id), as: :turbo_stream

    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "running", run.status
    assert_import_sources_turbo_feedback(message: "Stop für Merge-Run ##{run.id} wurde angefordert.")
    assert_import_run_row_in_response(run)
    assert_includes response.body, "stopping"
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

    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(3)", text: "stopping"
    assert_select "tr[data-run-id='#{run.id}'] td:last-child", text: /Stop angefordert/, count: 0
    assert_select "#import-runs-tab-llm-enrichment .import-runs-tab-indicator-stopping", text: "1"
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
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(1) code", text: merge_run.id.to_s
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(4)", text: "5"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(5)", text: "3"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(6)", text: "1"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(7)", text: "2"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(8)", text: "1"
    assert_select "tr[data-run-id='#{merge_run.id}'] td:nth-child(9)", text: "2"
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
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(1) code", text: run.id.to_s
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(5)", text: "7"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(6)", text: "0"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(7)", text: "7"
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
        "api_calls_completed_count" => 5
      }
    )

    get backend_import_sources_url
    assert_response :success

    assert_select "h3", text: "LLM-Enrichment Jobs"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(1) code", text: run.id.to_s
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(4)", text: "120"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(5)", text: "15"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(6)", text: "40"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(7)", text: "5"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(8)", text: "2"
  end

  test "should label single event llm enrichment runs in jobs table" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "queued",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: {
        "trigger_scope" => "single_event",
        "target_event_id" => events(:published_one).id,
        "target_event_context" => "Published Artist · Published Event · 01.06.2026 22:00"
      }
    )

    get backend_import_sources_url(section: :llm_enrichment)
    assert_response :success

    assert_select "tr[data-run-id='#{run.id}'] td:first-child", text: /Einzel-Event · ##{events(:published_one).id}/
  end

  test "should show llm genre grouping runs in dedicated jobs table" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_genre_grouping",
      started_at: 1.minute.ago,
      fetched_count: 320,
      filtered_count: 4,
      imported_count: 30,
      upserted_count: 2,
      failed_count: 1,
      metadata: {}
    )

    get backend_import_sources_url
    assert_response :success

    assert_select "h3", text: "LLM-Genre-Gruppierung Jobs"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(1) code", text: run.id.to_s
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(4)", text: "320"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(5)", text: "4"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(6)", text: "30"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(7)", text: "2"
    assert_select "tr[data-run-id='#{run.id}'] td:nth-child(8)", text: "1"
  end

  test "should render explanatory text for each importer block" do
    get backend_import_sources_url
    assert_response :success

    assert_includes response.body, "Diese Jobs holen Rohdaten direkt von Easyticket, Eventim und Reservix ab"
    assert_includes response.body, "Automatischer Lauf täglich um 03:05 Uhr (Europe/Berlin)."
    assert_includes response.body, "Diese Jobs lesen die aktuellen Rohimporte aller Quellen"
    assert_includes response.body, "Automatischer Lauf täglich um 04:05 Uhr (Europe/Berlin)."
    assert_includes response.body, "Diese Jobs ergänzen bereits gemergte Events um verdichtete redaktionelle Metadaten"
    assert_includes response.body, "Automatischer Lauf täglich um 05:05 Uhr (Europe/Berlin)."
    assert_includes response.body, "Diese Jobs analysieren die im System vorhandenen Rohgenre-Werte"
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

  test "should show single event llm enrichment context on detail page" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "queued",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: {
        "trigger_scope" => "single_event",
        "target_event_id" => events(:published_one).id,
        "target_event_context" => "Published Artist · Published Event · 01.06.2026 22:00"
      }
    )

    get backend_import_run_url(run, section: :llm_enrichment)
    assert_response :success

    assert_includes response.body, "Einzel-Event"
    assert_includes response.body, "Published Artist · Published Event · 01.06.2026 22:00"
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
    easyticket_runs = payload["runs"].select { |run| run["source_type"] == "easyticket" }
    assert_equal Backend::ImportRunsBroadcaster::RECENT_RUNS_LIMIT_PER_BLOCK, easyticket_runs.size
  end

  test "should show llm enrichment runs even when more than ten newer runs exist in other blocks" do
    llm_run = ImportRun.create!(
      import_source: @eventim_source,
      status: "succeeded",
      source_type: "llm_enrichment",
      started_at: 30.minutes.ago,
      finished_at: 29.minutes.ago
    )

    12.times do |index|
      ImportRun.create!(
        import_source: @source,
        status: "succeeded",
        source_type: "merge",
        started_at: (index + 1).minutes.ago,
        finished_at: index.minutes.ago
      )
    end

    get backend_import_sources_url
    assert_response :success

    assert_select "h3", text: "LLM-Enrichment Jobs"
    assert_select "tr[data-run-id='#{llm_run.id}']"
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

    run = ImportRun.where(source_type: "merge").order(:created_at).last
    assert_equal "running", run.status
    assert run.metadata["job_id"].present?
    assert_redirected_to backend_import_sources_url
    follow_redirect!
    assert_includes response.body, "Merge-Sync wurde gestartet."
  end

  test "should respond with turbo stream when enqueueing merge sync from import sources page" do
    assert_enqueued_jobs 1, only: Merging::SyncImportedEventsJob do
      post sync_imported_events_backend_import_sources_url, as: :turbo_stream
    end

    run = ImportRun.where(source_type: "merge").order(:created_at).last
    assert_equal "running", run.status
    assert run.metadata["job_id"].present?

    assert_import_sources_turbo_feedback(message: "Merge-Sync wurde gestartet.")
    assert_import_run_row_in_response(run)
  end

  test "should not enqueue merge sync when another merge run is already active" do
    existing_run = @source.import_runs.create!(
      status: "running",
      source_type: "merge",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    assert_no_enqueued_jobs only: Merging::SyncImportedEventsJob do
      post sync_imported_events_backend_import_sources_url, as: :turbo_stream
    end

    assert_import_sources_turbo_feedback(message: "Ein Merge-Run läuft bereits (Run ##{existing_run.id}).")
    assert_import_run_row_in_response(existing_run)
  end

  test "should render llm enrichment actions on index without rerun button" do
    get backend_import_sources_url

    assert_response :success
    assert_includes response.body, "LLM-Enrichment starten"
    assert_not_includes response.body, "Zukünftige Events neu anreichern"
    assert_includes response.body, "Edit"
    assert_select "a[href='#{edit_backend_settings_path(section: :llm_enrichment)}']", text: "Edit"
    assert_select "form[action='#{run_llm_enrichment_backend_import_sources_path(section: :llm_enrichment)}'] .button", text: "LLM-Enrichment starten"
    assert_select "form[action='#{rerun_llm_enrichment_backend_import_sources_path(section: :llm_enrichment)}']", count: 0
  end

  test "should render llm genre grouping button on index" do
    get backend_import_sources_url

    assert_response :success
    assert_includes response.body, "LLM-Genre-Gruppierung starten"
    assert_select "a[href='#{edit_backend_settings_path(section: :llm_genre_grouping)}']", text: "Edit"
  end

  test "should enqueue llm enrichment run from import sources page" do
    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      post run_llm_enrichment_backend_import_sources_url(section: :llm_enrichment)
    end

    run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last
    assert_equal "queued", run.status
    assert_equal false, ActiveModel::Type::Boolean.new.cast(run.metadata["refresh_existing"])
    assert run.metadata["job_id"].present?

    assert_redirected_to backend_import_sources_url(section: :llm_enrichment)
    follow_redirect!
    assert_includes response.body, "LLM-Enrichment wurde gestartet."
  end

  test "should respond with turbo stream when enqueueing llm enrichment run from import sources page" do
    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      post run_llm_enrichment_backend_import_sources_url(section: :llm_enrichment), as: :turbo_stream
    end

    run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last
    assert_equal "queued", run.status
    assert_equal false, ActiveModel::Type::Boolean.new.cast(run.metadata["refresh_existing"])
    assert run.metadata["job_id"].present?

    assert_import_sources_turbo_feedback(message: "LLM-Enrichment wurde gestartet.")
    assert_import_run_row_in_response(run)
  end

  test "should enqueue llm enrichment rerun from import sources page" do
    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      post rerun_llm_enrichment_backend_import_sources_url(section: :llm_enrichment)
    end

    run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last
    assert_equal "queued", run.status
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.metadata["refresh_existing"])
    assert run.metadata["job_id"].present?

    assert_redirected_to backend_import_sources_url(section: :llm_enrichment)
    follow_redirect!
    assert_includes response.body, "LLM-Enrichment-Re-Run für zukünftige Events wurde gestartet."
  end

  test "should respond with turbo stream when enqueueing llm enrichment rerun from import sources page" do
    assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
      post rerun_llm_enrichment_backend_import_sources_url(section: :llm_enrichment), as: :turbo_stream
    end

    run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last
    assert_equal "queued", run.status
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.metadata["refresh_existing"])
    assert run.metadata["job_id"].present?

    assert_import_sources_turbo_feedback(message: "LLM-Enrichment-Re-Run für zukünftige Events wurde gestartet.")
    assert_import_run_row_in_response(run)
  end

  test "should queue llm enrichment run when another llm run is active" do
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

    queued_run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last

    assert_equal "queued", queued_run.status
    assert_equal false, ActiveModel::Type::Boolean.new.cast(queued_run.metadata["refresh_existing"])
    assert_redirected_to backend_import_sources_url
    follow_redirect!
    assert_includes response.body, "LLM-Enrichment wurde zur Warteschlange hinzugefügt (Position 1)."
  end

  test "should queue llm enrichment rerun when another llm run is active" do
    ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    assert_no_enqueued_jobs only: Importing::LlmEnrichment::RunJob do
      post rerun_llm_enrichment_backend_import_sources_url(section: :llm_enrichment)
    end

    queued_run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last

    assert_equal "queued", queued_run.status
    assert_equal true, ActiveModel::Type::Boolean.new.cast(queued_run.metadata["refresh_existing"])
    assert_redirected_to backend_import_sources_url(section: :llm_enrichment)
    follow_redirect!
    assert_includes response.body, "LLM-Enrichment-Re-Run für zukünftige Events wurde zur Warteschlange hinzugefügt (Position 1)."
  end

  test "should respond with turbo stream when queueing llm enrichment behind an active run" do
    ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    assert_no_enqueued_jobs only: Importing::LlmEnrichment::RunJob do
      post run_llm_enrichment_backend_import_sources_url, as: :turbo_stream
    end

    queued_run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last

    assert_equal "queued", queued_run.status
    assert_import_sources_turbo_feedback(message: "LLM-Enrichment wurde zur Warteschlange hinzugefügt (Position 1).")
    assert_import_run_row_in_response(queued_run)
  end

  test "should queue llm enrichment run when a rerun is active" do
    ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 2.minutes.ago,
      metadata: { "refresh_existing" => true }
    )

    assert_no_enqueued_jobs only: Importing::LlmEnrichment::RunJob do
      post run_llm_enrichment_backend_import_sources_url(section: :llm_enrichment), as: :turbo_stream
    end

    queued_run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last

    assert_equal "queued", queued_run.status
    assert_import_sources_turbo_feedback(message: "LLM-Enrichment wurde zur Warteschlange hinzugefügt (Position 1).")
    assert_import_run_row_in_response(queued_run)
  end

  test "should request stop for a running llm enrichment run" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_llm_enrichment_run_backend_import_sources_url(run_id: run.id, section: :llm_enrichment)

    assert_redirected_to backend_import_sources_url(section: :llm_enrichment)
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "running", run.status
    follow_redirect!
    assert_includes response.body, "Stop für LLM-Enrichment"
  end

  test "should respond with turbo stream when stopping a running llm enrichment run" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_llm_enrichment_run_backend_import_sources_url(run_id: run.id, section: :llm_enrichment), as: :turbo_stream

    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "running", run.status
    assert_import_sources_turbo_feedback(message: "Stop für LLM-Enrichment (Run ##{run.id}) wurde angefordert.")
    assert_import_run_row_in_response(run)
    assert_includes response.body, "stopping"
  end

  test "should immediately cancel a running single event llm enrichment run" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_enrichment",
      started_at: 2.minutes.ago,
      metadata: {
        "trigger_scope" => "single_event",
        "target_event_id" => events(:published_one).id
      }
    )

    post stop_llm_enrichment_run_backend_import_sources_url(run_id: run.id, section: :llm_enrichment), as: :turbo_stream

    assert_equal "canceled", run.reload.status
    assert_equal "Force-stopped single-event run", run.metadata["stop_release_reason"]
    assert_import_sources_turbo_feedback(message: "LLM-Enrichment (Run ##{run.id}) wurde sofort gestoppt.")
    assert_import_run_row_in_response(run)
    assert_includes response.body, "canceled"
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

  test "should render cancel action for queued llm enrichment jobs" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "queued",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: {}
    )

    get backend_import_sources_url(section: :llm_enrichment)
    assert_response :success

    assert_select "tr[data-run-id='#{run.id}'] td:last-child form button", text: "Abbrechen"
  end

  test "should include llm enrichment runs in recent runs json" do
    llm_run = ImportRun.create!(
      import_source: @eventim_source,
      status: "queued",
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

  test "should render queued indicator for llm enrichment tab" do
    ImportRun.create!(
      import_source: @eventim_source,
      status: "queued",
      source_type: "llm_enrichment",
      started_at: 1.minute.ago,
      metadata: {}
    )

    get backend_import_sources_url
    assert_response :success

    assert_select "#import-runs-tab-llm-enrichment .import-runs-tab-indicator-queued", text: "1"
  end

  test "should cancel queued llm enrichment run" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "queued",
      source_type: "llm_enrichment",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_llm_enrichment_run_backend_import_sources_url(run_id: run.id, section: :llm_enrichment)

    assert_redirected_to backend_import_sources_url(section: :llm_enrichment)
    assert_equal "canceled", run.reload.status
    follow_redirect!
    assert_includes response.body, "wurde aus der Warteschlange entfernt"
  end

  test "should enqueue llm genre grouping run from import sources page" do
    assert_enqueued_jobs 1, only: Importing::LlmGenreGrouping::RunJob do
      post run_llm_genre_grouping_backend_import_sources_url(section: :llm_genre_grouping)
    end

    run = ImportRun.where(source_type: "llm_genre_grouping").order(:created_at).last
    assert_equal "running", run.status

    assert_redirected_to backend_import_sources_url(section: :llm_genre_grouping)
    follow_redirect!
    assert_includes response.body, "LLM-Genre-Gruppierung wurde gestartet."
  end

  test "should respond with turbo stream when enqueueing llm genre grouping run from import sources page" do
    assert_enqueued_jobs 1, only: Importing::LlmGenreGrouping::RunJob do
      post run_llm_genre_grouping_backend_import_sources_url(section: :llm_genre_grouping), as: :turbo_stream
    end

    run = ImportRun.where(source_type: "llm_genre_grouping").order(:created_at).last
    assert_equal "running", run.status

    assert_import_sources_turbo_feedback(message: "LLM-Genre-Gruppierung wurde gestartet.")
    assert_import_run_row_in_response(run)
  end

  test "should not enqueue llm genre grouping run when another grouping run is active" do
    existing_run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_genre_grouping",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    assert_no_enqueued_jobs only: Importing::LlmGenreGrouping::RunJob do
      post run_llm_genre_grouping_backend_import_sources_url, as: :turbo_stream
    end

    assert_import_sources_turbo_feedback(message: "Ein LLM-Genre-Gruppierungs-Lauf läuft bereits (Run ##{existing_run.id}).")
    assert_import_run_row_in_response(existing_run)
  end

  test "should request stop for a running llm genre grouping run" do
    run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_genre_grouping",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_llm_genre_grouping_run_backend_import_sources_url(run_id: run.id, section: :llm_genre_grouping)

    assert_redirected_to backend_import_sources_url(section: :llm_genre_grouping)
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "running", run.status
    follow_redirect!
    assert_includes response.body, "Stop für LLM-Genre-Gruppierung"
  end

  test "should include llm genre grouping runs in recent runs json" do
    llm_run = ImportRun.create!(
      import_source: @eventim_source,
      status: "running",
      source_type: "llm_genre_grouping",
      started_at: 1.minute.ago,
      metadata: {}
    )

    get backend_import_sources_url(format: :json)
    assert_response :success

    payload = JSON.parse(response.body)
    run_payload = payload.fetch("runs").find { |run| run["id"] == llm_run.id }

    assert run_payload.present?
    assert_equal "llm_genre_grouping", run_payload["source_type"]
    assert_equal true, run_payload["can_stop"]
    assert_includes run_payload["stop_url"], "stop_llm_genre_grouping_run"
  end

  test "should enqueue easyticket run" do
    assert_enqueued_jobs 1 do
      post run_easyticket_backend_import_source_url(@source, section: :raw_importer)
    end
    assert_redirected_to backend_import_sources_url(section: :raw_importer)
    follow_redirect!
    assert_includes response.body, "Easyticket-Import wurde gestartet."
    assert_equal "running", @source.import_runs.order(:created_at).last.status
  end

  test "should respond with turbo stream when enqueueing easyticket run" do
    assert_enqueued_jobs 1 do
      post run_easyticket_backend_import_source_url(@source, section: :raw_importer), as: :turbo_stream
    end

    run = @source.import_runs.order(:created_at).last

    assert_import_sources_turbo_feedback(message: "Easyticket-Import wurde gestartet.")
    assert_import_run_row_in_response(run)
  end

  test "should respond with turbo stream when another easyticket run is already active" do
    existing_run = @source.import_runs.create!(
      status: "running",
      source_type: "easyticket",
      started_at: 10.minutes.ago,
      metadata: {}
    )

    assert_no_enqueued_jobs do
      post run_easyticket_backend_import_source_url(@source), as: :turbo_stream
    end

    assert_import_sources_turbo_feedback(message: "Ein Easyticket-Import läuft bereits (Run ##{existing_run.id}).")
    assert_import_run_row_in_response(existing_run)
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

    post stop_easyticket_run_backend_import_source_url(@source, section: :raw_importer), params: { run_id: run.id }

    assert_redirected_to backend_import_sources_url(section: :raw_importer)
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "running", run.status
  end

  test "should respond with turbo stream when stopping a running easyticket run" do
    run = @source.import_runs.create!(
      status: "running",
      source_type: "easyticket",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_easyticket_run_backend_import_source_url(@source, section: :raw_importer), params: { run_id: run.id }, as: :turbo_stream

    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "running", run.status
    assert_import_sources_turbo_feedback(message: "Stop für Easyticket-Import (Run ##{run.id}) wurde angefordert.")
    assert_import_run_row_in_response(run)
    assert_includes response.body, "stopping"
  end

  test "should not request stop when no running run exists" do
    post stop_easyticket_run_backend_import_source_url(@source), params: { run_id: 999_999 }

    assert_redirected_to backend_import_sources_url
  end

  test "should enqueue eventim run" do
    assert_enqueued_jobs 1 do
      post run_eventim_backend_import_source_url(@eventim_source, section: :raw_importer)
    end

    assert_redirected_to backend_import_sources_url(section: :raw_importer)
    follow_redirect!
    assert_includes response.body, "Eventim-Import wurde gestartet."
    assert_equal "running", @eventim_source.import_runs.order(:created_at).last.status
  end

  test "should respond with turbo stream when enqueueing eventim run" do
    assert_enqueued_jobs 1 do
      post run_eventim_backend_import_source_url(@eventim_source, section: :raw_importer), as: :turbo_stream
    end

    run = @eventim_source.import_runs.order(:created_at).last

    assert_import_sources_turbo_feedback(message: "Eventim-Import wurde gestartet.")
    assert_import_run_row_in_response(run)
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

  test "should respond with turbo stream when another eventim run is already active" do
    existing_run = @eventim_source.import_runs.create!(
      status: "running",
      source_type: "eventim",
      started_at: 10.minutes.ago,
      metadata: {}
    )

    assert_no_enqueued_jobs do
      post run_eventim_backend_import_source_url(@eventim_source), as: :turbo_stream
    end

    assert_import_sources_turbo_feedback(message: "Ein Eventim-Import läuft bereits (Run ##{existing_run.id}).")
    assert_import_run_row_in_response(existing_run)
  end

  test "should respond with turbo stream when enqueueing reservix run" do
    assert_enqueued_jobs 1 do
      post run_reservix_backend_import_source_url(@reservix_source, section: :raw_importer), as: :turbo_stream
    end

    run = @reservix_source.import_runs.order(:created_at).last
    assert_equal "running", run.status

    assert_import_sources_turbo_feedback(message: "Reservix-Import wurde gestartet.")
    assert_import_run_row_in_response(run)
  end

  test "should respond with turbo stream when another reservix run is already active" do
    existing_run = @reservix_source.import_runs.create!(
      status: "running",
      source_type: "reservix",
      started_at: 10.minutes.ago,
      metadata: {}
    )

    assert_no_enqueued_jobs do
      post run_reservix_backend_import_source_url(@reservix_source), as: :turbo_stream
    end

    assert_import_sources_turbo_feedback(message: "Ein Reservix-Import läuft bereits (Run ##{existing_run.id}).")
    assert_import_run_row_in_response(existing_run)
  end

  test "should request stop for a running eventim run" do
    run = @eventim_source.import_runs.create!(
      status: "running",
      source_type: "eventim",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_eventim_run_backend_import_source_url(@eventim_source, section: :raw_importer), params: { run_id: run.id }

    assert_redirected_to backend_import_sources_url(section: :raw_importer)
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "running", run.status
  end

  test "should respond with turbo stream when stopping a running eventim run" do
    run = @eventim_source.import_runs.create!(
      status: "running",
      source_type: "eventim",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_eventim_run_backend_import_source_url(@eventim_source, section: :raw_importer), params: { run_id: run.id }, as: :turbo_stream

    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "running", run.status
    assert_import_sources_turbo_feedback(message: "Stop für Eventim-Import (Run ##{run.id}) wurde angefordert.")
    assert_import_run_row_in_response(run)
    assert_includes response.body, "stopping"
  end

  test "should request stop for a running reservix run" do
    run = @reservix_source.import_runs.create!(
      status: "running",
      source_type: "reservix",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_reservix_run_backend_import_source_url(@reservix_source, section: :raw_importer), params: { run_id: run.id }

    assert_redirected_to backend_import_sources_url(section: :raw_importer)
    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "running", run.status
  end

  test "should respond with turbo stream when stopping a running reservix run" do
    run = @reservix_source.import_runs.create!(
      status: "running",
      source_type: "reservix",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    post stop_reservix_run_backend_import_source_url(@reservix_source, section: :raw_importer), params: { run_id: run.id }, as: :turbo_stream

    assert_equal true, ActiveModel::Type::Boolean.new.cast(run.reload.metadata["stop_requested"])
    assert_equal "running", run.status
    assert_import_sources_turbo_feedback(message: "Stop für Reservix-Import (Run ##{run.id}) wurde angefordert.")
    assert_import_run_row_in_response(run)
    assert_includes response.body, "stopping"
  end

  private

  def assert_import_sources_turbo_feedback(message:)
    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    assert_includes response.body, "action=\"update\" target=\"flash-messages\""
    assert_includes response.body, "target=\"flash-messages\""
    assert_includes response.body, "target=\"import-runs-live-shell\""
    assert_includes response.body, message
  end

  def assert_import_run_row_in_response(run)
    assert_includes response.body, "data-run-id=\"#{run.id}\""
  end
end
