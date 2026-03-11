require "test_helper"

class Backend::ImportSources::RunMaintenanceTest < ActiveSupport::TestCase
  setup do
    @registry = Backend::ImportSources::ImporterRegistry.new
    @maintenance = Backend::ImportSources::RunMaintenance.new(registry: @registry)
    @source = import_sources(:two)
  end

  test "does not mark unclaimed running run as heartbeat stale" do
    run = @source.import_runs.create!(
      status: "running",
      source_type: "eventim",
      started_at: 5.minutes.ago,
      metadata: { "triggered_at" => 5.minutes.ago.iso8601 }
    )
    run.update_columns(updated_at: 5.minutes.ago)

    assert_equal false, @maintenance.release_stale_running_run!(run)
    assert_equal "running", run.reload.status
  end

  test "marks claimed running run as heartbeat stale" do
    run = @source.import_runs.create!(
      status: "running",
      source_type: "eventim",
      started_at: 5.minutes.ago,
      metadata: {
        "triggered_at" => 5.minutes.ago.iso8601,
        "execution_started_at" => 4.minutes.ago.iso8601
      }
    )
    run.update_columns(updated_at: (Importing::Eventim::Importer::RUN_HEARTBEAT_STALE_AFTER + 10.seconds).ago)

    assert_equal true, @maintenance.release_stale_running_run!(run)
    assert_equal "failed", run.reload.status
    assert_includes run.metadata["stale_release_reason"], "heartbeat timeout"
  end
end
