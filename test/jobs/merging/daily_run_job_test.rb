require "test_helper"

class Merging::DailyRunJobTest < ActiveJob::TestCase
  test "enqueues a merge sync run with scheduler metadata" do
    assert_difference -> { ImportRun.where(source_type: "merge").count }, 1 do
      assert_enqueued_jobs 1, only: Merging::SyncImportedEventsJob do
        Merging::DailyRunJob.perform_now
      end
    end

    run = ImportRun.where(source_type: "merge").order(:created_at).last
    assert_equal "running", run.status
    assert_equal "scheduler", run.metadata["triggered_by"]
    assert_equal "daily_merge_run", run.metadata["schedule_name"]
    assert run.metadata["job_id"].present?
  end

  test "does not enqueue a merge sync run while another merge run is active" do
    ImportRun.create!(
      import_source: import_sources(:two),
      source_type: "merge",
      status: "running",
      started_at: 2.minutes.ago,
      metadata: {}
    )

    assert_no_difference -> { ImportRun.where(source_type: "merge").count } do
      assert_no_enqueued_jobs only: Merging::SyncImportedEventsJob do
        Merging::DailyRunJob.perform_now
      end
    end
  end
end
