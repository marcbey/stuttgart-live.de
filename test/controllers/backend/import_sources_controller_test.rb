require "test_helper"

class Backend::ImportSourcesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as(users(:one))
    @source = import_sources(:one)
    @eventim_source = import_sources(:two)
  end

  test "should get index" do
    get backend_import_sources_url
    assert_response :success
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
    patch backend_import_source_url(@source), params: {
      import_source: {
        name: "Easyticket Neu",
        active: "1",
        location_whitelist_text: "Stuttgart\nEsslingen am Neckar"
      }
    }
    assert_redirected_to backend_import_sources_url
  end

  test "should enqueue easyticket run" do
    assert_enqueued_jobs 1 do
      post run_easyticket_backend_import_source_url(@source)
    end
    assert_redirected_to backend_import_sources_url
    follow_redirect!
    assert_not_includes response.body, "Easyticket-Import wurde gestartet."
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

  test "should not enqueue when easyticket run is already active" do
    @source.import_runs.create!(
      status: "running",
      source_type: "easyticket",
      started_at: 10.minutes.ago
    )

    assert_no_enqueued_jobs do
      post run_easyticket_backend_import_source_url(@source)
    end

    assert_redirected_to backend_import_sources_url
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
  end

  test "should not enqueue when eventim run is already active" do
    @eventim_source.import_runs.create!(
      status: "running",
      source_type: "eventim",
      started_at: 10.minutes.ago
    )

    assert_no_enqueued_jobs do
      post run_eventim_backend_import_source_url(@eventim_source)
    end

    assert_redirected_to backend_import_sources_url
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
end
