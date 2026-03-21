require "test_helper"

module Importing
  module LlmGenreGrouping
    class RunJobTest < ActiveJob::TestCase
      setup do
        @run = import_sources(:two).import_runs.create!(
          source_type: "llm_genre_grouping",
          status: "running",
          started_at: 1.minute.ago,
          metadata: {}
        )
      end

      test "marks run as succeeded and stores metrics" do
        fake_result = Importing::LlmGenreGrouping::Importer::Result.new(
          selected_count: 12,
          skipped_count: 1,
          groups_count: 3,
          requests_count: 2,
          snapshot_id: 7,
          snapshot_key: SecureRandom.uuid,
          requested_group_count: 30,
          effective_group_count: 3,
          model: "gpt-5-mini",
          canceled: false
        )
        fake_importer = Struct.new(:call).new(fake_result)

        importer_class = Importing::LlmGenreGrouping::Importer.singleton_class
        importer_class.alias_method :__original_new_for_test, :new
        importer_class.define_method(:new) { |*| fake_importer }

        RunJob.perform_now(@run.id)

        @run.reload
        assert_equal "succeeded", @run.status
        assert_equal 12, @run.fetched_count
        assert_equal 1, @run.filtered_count
        assert_equal 3, @run.imported_count
        assert_equal 2, @run.upserted_count
        assert_equal 7, @run.metadata["snapshot_id"]
      ensure
        importer_class.alias_method :new, :__original_new_for_test
        importer_class.remove_method :__original_new_for_test
      end

      test "stores import_run_error when importer fails and keeps existing snapshots unchanged" do
        existing_snapshot = ImportRun.create!(
          import_source: import_sources(:one),
          source_type: "llm_genre_grouping",
          status: "succeeded",
          started_at: 2.minutes.ago,
          finished_at: 1.minute.ago
        ).create_llm_genre_grouping_snapshot!(
          active: true,
          requested_group_count: 30,
          effective_group_count: 30,
          source_genres_count: 100,
          model: "gpt-5-mini",
          prompt_template_digest: "digest",
          request_payload: {},
          raw_response: {}
        )

        fake_importer = Struct.new(:call).new(nil)
        def fake_importer.call
          raise "grouping crashed"
        end

        importer_class = Importing::LlmGenreGrouping::Importer.singleton_class
        importer_class.alias_method :__original_new_for_test, :new
        importer_class.define_method(:new) { |*| fake_importer }

        assert_raises RuntimeError do
          RunJob.perform_now(@run.id)
        end

        @run.reload
        assert_equal "failed", @run.status
        assert_equal 1, @run.import_run_errors.count
        assert_equal "llm_genre_grouping", @run.import_run_errors.last.source_type
        assert_equal true, existing_snapshot.reload.active
      ensure
        importer_class.alias_method :new, :__original_new_for_test
        importer_class.remove_method :__original_new_for_test
      end

      test "marks run as canceled when importer stops cooperatively" do
        fake_result = Importing::LlmGenreGrouping::Importer::Result.new(
          selected_count: 12,
          skipped_count: 1,
          groups_count: 0,
          requests_count: 1,
          snapshot_id: nil,
          snapshot_key: nil,
          requested_group_count: 30,
          effective_group_count: 12,
          model: "gpt-5-mini",
          canceled: true
        )
        fake_importer = Struct.new(:call).new(fake_result)

        importer_class = Importing::LlmGenreGrouping::Importer.singleton_class
        importer_class.alias_method :__original_new_for_test, :new
        importer_class.define_method(:new) { |*| fake_importer }

        RunJob.perform_now(@run.id)

        @run.reload
        assert_equal "canceled", @run.status
        assert_equal 12, @run.fetched_count
        assert_equal 1, @run.filtered_count
        assert_equal 0, @run.imported_count
        assert_equal "Stopped by user", @run.metadata["stop_release_reason"]
      ensure
        importer_class.alias_method :new, :__original_new_for_test
        importer_class.remove_method :__original_new_for_test
      end
    end
  end
end
