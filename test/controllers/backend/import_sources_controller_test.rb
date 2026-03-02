require "test_helper"

class Backend::ImportSourcesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @source = import_sources(:one)
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
    assert payload["runs"].first.key?("status_label")
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
  end

  test "should not request stop when no running run exists" do
    post stop_easyticket_run_backend_import_source_url(@source), params: { run_id: 999_999 }

    assert_redirected_to backend_import_sources_url
  end
end
