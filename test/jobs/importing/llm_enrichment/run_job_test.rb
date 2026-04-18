require "test_helper"

module Importing
  module LlmEnrichment
    class RunJobTest < ActiveJob::TestCase
      setup do
        @source = import_sources(:two)
        @run = @source.import_runs.create!(
          source_type: "llm_enrichment",
          status: "queued",
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
          web_search_provider: "serpapi",
          links_checked_count: 7,
          links_rejected_count: 2,
          links_unverifiable_count: 1,
          web_search_request_count: 9,
          web_search_candidate_count: 14,
          links_found_via_web_search_count: 4,
          links_null_after_link_lookup_count: 8,
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
        assert_equal "serpapi", @run.metadata["web_search_provider"]
        assert_equal 7, @run.metadata["links_checked_count"]
        assert_equal 2, @run.metadata["links_rejected_count"]
        assert_equal 1, @run.metadata["links_unverifiable_count"]
        assert_equal 9, @run.metadata["web_search_request_count"]
        assert_equal 14, @run.metadata["web_search_candidate_count"]
        assert_equal 4, @run.metadata["links_found_via_web_search_count"]
        assert_equal 8, @run.metadata["links_null_after_link_lookup_count"]
        assert_equal true, ActiveModel::Type::Boolean.new.cast(@run.metadata["refresh_existing"])
        assert @run.metadata["execution_started_at"].present?
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
          web_search_provider: "openwebninja",
          links_checked_count: 4,
          links_rejected_count: 1,
          links_unverifiable_count: 2,
          web_search_request_count: 5,
          web_search_candidate_count: 11,
          links_found_via_web_search_count: 2,
          links_null_after_link_lookup_count: 6,
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
        assert_equal "openwebninja", @run.metadata["web_search_provider"]
        assert_equal 4, @run.metadata["links_checked_count"]
        assert_equal 1, @run.metadata["links_rejected_count"]
        assert_equal 2, @run.metadata["links_unverifiable_count"]
        assert_equal 5, @run.metadata["web_search_request_count"]
        assert_equal 11, @run.metadata["web_search_candidate_count"]
        assert_equal 2, @run.metadata["links_found_via_web_search_count"]
        assert_equal 6, @run.metadata["links_null_after_link_lookup_count"]
        assert_equal "Stopped by user", @run.metadata["stop_release_reason"]
      ensure
        importer_class.alias_method :new, :__original_new_for_test
        importer_class.remove_method :__original_new_for_test
      end

      test "does not process a queued run that was canceled before claim" do
        @run.update!(status: "canceled", finished_at: Time.current)

        importer_class = Importing::LlmEnrichment::Importer.singleton_class
        importer_class.alias_method :__original_new_for_test, :new
        importer_class.define_method(:new) { raise "should not build importer" }

        RunJob.perform_now(@run.id)
        assert_equal "canceled", @run.reload.status
      ensure
        importer_class.alias_method :new, :__original_new_for_test
        importer_class.remove_method :__original_new_for_test
      end

      test "dispatches the next queued run after finishing" do
        next_run = @source.import_runs.create!(
          source_type: "llm_enrichment",
          status: "queued",
          started_at: Time.current,
          metadata: {}
        )

        fake_result = Importing::LlmEnrichment::Importer::Result.new(
          selected_count: 1,
          skipped_count: 0,
          enriched_count: 1,
          batches_count: 1,
          merge_run_id: nil,
          model: "gpt-5-mini",
          web_search_provider: "serpapi",
          links_checked_count: 0,
          links_rejected_count: 0,
          links_unverifiable_count: 0,
          web_search_request_count: 0,
          web_search_candidate_count: 0,
          links_found_via_web_search_count: 0,
          links_null_after_link_lookup_count: 0,
          canceled: false
        )
        fake_importer = Struct.new(:call).new(fake_result)

        importer_class = Importing::LlmEnrichment::Importer.singleton_class
        importer_class.alias_method :__original_new_for_test, :new
        importer_class.define_method(:new) { |*| fake_importer }

        assert_enqueued_jobs 1, only: RunJob do
          RunJob.perform_now(@run.id)
        end

        assert next_run.reload.metadata["job_id"].present?
      ensure
        importer_class.alias_method :new, :__original_new_for_test
        importer_class.remove_method :__original_new_for_test
      end
    end
  end
end
