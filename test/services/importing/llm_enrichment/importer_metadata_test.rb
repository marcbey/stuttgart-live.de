require "test_helper"

module Importing
  module LlmEnrichment
    class ImporterMetadataTest < ActiveSupport::TestCase
      setup do
        @source = import_sources(:two)
        @run = @source.import_runs.create!(
          source_type: "llm_enrichment",
          status: "running",
          started_at: 1.minute.ago,
          metadata: { "existing" => "value" }
        )
        @importer = Importer.new(run: @run, client: Struct.new(:model).new("gpt-5-mini"))
      end

      test "update_run_progress preserves externally written stop flag" do
        @run.update!(metadata: @run.metadata.merge("stop_requested" => true, "stop_requested_at" => Time.current.iso8601))

        @importer.send(
          :update_run_progress!,
          selected_count: 10,
          skipped_count: 2,
          enriched_count: 3,
          batches_count: 4,
          batches_processed: 1
        )

        metadata = @run.reload.metadata.deep_stringify_keys
        assert_equal true, ActiveModel::Type::Boolean.new.cast(metadata["stop_requested"])
        assert_equal "value", metadata["existing"]
        assert_equal 10, metadata["events_selected_count"]
      end

      test "touch_run_heartbeat preserves externally written stop flag" do
        @run.update!(metadata: @run.metadata.merge("stop_requested" => true, "stop_requested_at" => Time.current.iso8601))

        @importer.send(:touch_run_heartbeat!, "current_batch" => 2)

        metadata = @run.reload.metadata.deep_stringify_keys
        assert_equal true, ActiveModel::Type::Boolean.new.cast(metadata["stop_requested"])
        assert_equal 2, metadata["current_batch"]
      end

      test "update_run_progress does not modify a run that is no longer running" do
        @run.update!(
          status: "failed",
          fetched_count: 1,
          filtered_count: 1,
          imported_count: 1,
          upserted_count: 1,
          metadata: @run.metadata.merge("events_enriched_count" => 1)
        )

        @importer.send(
          :update_run_progress!,
          selected_count: 10,
          skipped_count: 2,
          enriched_count: 3,
          batches_count: 4,
          batches_processed: 2
        )

        @run.reload
        assert_equal "failed", @run.status
        assert_equal 1, @run.fetched_count
        assert_equal 1, @run.imported_count
        assert_equal 1, @run.upserted_count
        assert_equal 1, @run.metadata["events_enriched_count"]
      end

      test "touch_run_heartbeat does not modify a run that is no longer running" do
        @run.update!(status: "failed")
        updated_at_before = @run.updated_at

        @importer.send(:touch_run_heartbeat!, "current_batch" => 7)

        @run.reload
        assert_equal "failed", @run.status
        assert_equal updated_at_before.to_i, @run.updated_at.to_i
        assert_nil @run.metadata["current_batch"]
      end
    end
  end
end
