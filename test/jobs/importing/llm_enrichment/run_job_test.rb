require "test_helper"

module Importing
  module LlmEnrichment
    class RunJobTest < ActiveJob::TestCase
      setup do
        @source = import_sources(:two)
        @run = @source.import_runs.create!(
          source_type: "llm_enrichment",
          status: "running",
          started_at: 1.minute.ago,
          metadata: {}
        )
      end

      test "marks run as succeeded and stores metrics" do
        @run.update!(metadata: @run.metadata.merge("refresh_existing" => true))
        fake_result = Importing::LlmEnrichment::Importer::Result.new(
          selected_count: 5,
          skipped_count: 2,
          enriched_count: 3,
          batches_count: 1,
          merge_run_id: nil,
          model: "gpt-5-mini",
          canceled: false
        )
        fake_importer = Struct.new(:call).new(fake_result)

        importer_class = Importing::LlmEnrichment::Importer.singleton_class
        importer_class.alias_method :__original_new_for_test, :new
        importer_class.define_method(:new) { |*| fake_importer }

        RunJob.perform_now(@run.id)

        @run.reload
        assert_equal "succeeded", @run.status
        assert_equal 5, @run.fetched_count
        assert_equal 2, @run.filtered_count
        assert_equal 3, @run.imported_count
        assert_equal 1, @run.upserted_count
        assert_nil @run.metadata["merge_run_id"]
        assert_equal "gpt-5-mini", @run.metadata["model"]
        assert_equal true, ActiveModel::Type::Boolean.new.cast(@run.metadata["refresh_existing"])
      ensure
        importer_class.alias_method :new, :__original_new_for_test
        importer_class.remove_method :__original_new_for_test
      end

      test "stores import_run_error when importer fails" do
        fake_importer = Struct.new(:call).new(nil)
        def fake_importer.call
          raise "llm crashed"
        end

        importer_class = Importing::LlmEnrichment::Importer.singleton_class
        importer_class.alias_method :__original_new_for_test, :new
        importer_class.define_method(:new) { |*| fake_importer }

        assert_raises RuntimeError do
          RunJob.perform_now(@run.id)
        end

        @run.reload
        assert_equal "failed", @run.status
        assert_equal 1, @run.import_run_errors.count
        assert_equal "llm_enrichment", @run.import_run_errors.last.source_type
      ensure
        importer_class.alias_method :new, :__original_new_for_test
        importer_class.remove_method :__original_new_for_test
      end

      test "marks run as canceled when importer stops cooperatively" do
        fake_result = Importing::LlmEnrichment::Importer::Result.new(
          selected_count: 5,
          skipped_count: 1,
          enriched_count: 2,
          batches_count: 3,
          merge_run_id: 123,
          model: "gpt-5-mini",
          canceled: true
        )
        fake_importer = Struct.new(:call).new(fake_result)

        importer_class = Importing::LlmEnrichment::Importer.singleton_class
        importer_class.alias_method :__original_new_for_test, :new
        importer_class.define_method(:new) { |*| fake_importer }

        RunJob.perform_now(@run.id)

        @run.reload
        assert_equal "canceled", @run.status
        assert_equal 5, @run.fetched_count
        assert_equal 1, @run.filtered_count
        assert_equal 2, @run.imported_count
        assert_equal "Stopped by user", @run.metadata["stop_release_reason"]
      ensure
        importer_class.alias_method :new, :__original_new_for_test
        importer_class.remove_method :__original_new_for_test
      end
    end
  end
end
