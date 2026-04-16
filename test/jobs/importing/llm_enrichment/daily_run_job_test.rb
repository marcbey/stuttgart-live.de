require "test_helper"

module Importing
  module LlmEnrichment
    class DailyRunJobTest < ActiveJob::TestCase
      test "enqueues a scheduled llm enrichment run" do
        assert_difference -> { ImportRun.where(source_type: "llm_enrichment").count }, 1 do
          assert_enqueued_jobs 1, only: Importing::LlmEnrichment::RunJob do
            DailyRunJob.perform_now
          end
        end

        run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last
        assert_equal "queued", run.status
        assert_equal "scheduler", run.metadata["triggered_by"]
        assert_equal "daily_llm_enrichment_run", run.metadata["schedule_name"]
        assert_equal false, ActiveModel::Type::Boolean.new.cast(run.metadata["refresh_existing"])
        assert_equal false, ActiveModel::Type::Boolean.new.cast(run.metadata["refresh_links_only"])
        assert run.metadata["job_id"].present?
      end

      test "queues behind an active llm enrichment run without dispatching immediately" do
        ImportRun.create!(
          import_source: import_sources(:two),
          source_type: "llm_enrichment",
          status: "running",
          started_at: 2.minutes.ago,
          metadata: {}
        )

        assert_difference -> { ImportRun.where(source_type: "llm_enrichment").count }, 1 do
          assert_no_enqueued_jobs only: Importing::LlmEnrichment::RunJob do
            DailyRunJob.perform_now
          end
        end

        run = ImportRun.where(source_type: "llm_enrichment").order(:created_at).last
        assert_equal "queued", run.status
        assert_equal "scheduler", run.metadata["triggered_by"]
        assert_equal "daily_llm_enrichment_run", run.metadata["schedule_name"]
        assert_nil run.metadata["job_id"]
      end
    end
  end
end
