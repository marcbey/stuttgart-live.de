require "test_helper"

class Merging::SyncImportedEventsJobTest < ActiveJob::TestCase
  test "creates merge import run with metrics" do
    assert_difference -> { ImportRun.where(source_type: "merge").count }, 1 do
      Merging::SyncImportedEventsJob.perform_now(last_run_at: Time.zone.parse("2026-03-14 09:00:00"))
    end

    run = ImportRun.where(source_type: "merge").order(:created_at).last
    assert_equal "succeeded", run.status
    assert run.fetched_count >= run.imported_count
    assert_equal 0, run.filtered_count
    assert run.fetched_count >= 0
    assert run.imported_count >= 0
    assert run.upserted_count >= 0
    assert run.failed_count >= 0
    assert run.metadata.key?("import_records_count")
    assert run.metadata.key?("groups_count")
    assert run.metadata.key?("events_created_count")
    assert run.metadata.key?("events_updated_count")
    assert run.metadata.key?("duplicate_matches_count")
    assert run.metadata.key?("offers_upserted_count")
    assert_equal "2026-03-14T09:00:00+01:00", run.metadata["last_run_at"]
  end

  test "stores import_run_error when merge sync fails" do
    failing_service =
      Class.new do
        def call
          raise "merge crashed"
        end
      end.new

    sync_class = Merging::SyncFromImports.singleton_class
    sync_class.alias_method :__original_new_for_test, :new
    sync_class.define_method(:new) { |*| failing_service }

    assert_raises RuntimeError do
      Merging::SyncImportedEventsJob.perform_now(last_run_at: Time.zone.parse("2026-03-14 09:00:00"))
    end

    run = ImportRun.where(source_type: "merge").order(:created_at).last
    assert_equal "failed", run.status
    assert_equal 1, run.import_run_errors.count

    error = run.import_run_errors.order(:created_at).last
    assert_equal "merge", error.source_type
    assert_equal "RuntimeError", error.error_class
    assert_includes error.message, "merge crashed"
  ensure
    sync_class.alias_method :new, :__original_new_for_test
    sync_class.remove_method :__original_new_for_test
  end

  test "passes merge run id to sync service" do
    captured_merge_run_id = nil
    fake_result = Merging::SyncFromImports::Result.new(
      import_records_count: 0,
      groups_count: 0,
      events_created_count: 0,
      events_updated_count: 0,
      duplicate_matches_count: 0,
      offers_upserted_count: 0
    )
    fake_service = Struct.new(:call).new(fake_result)

    sync_class = Merging::SyncFromImports.singleton_class
    sync_class.alias_method :__original_new_for_test, :new
    sync_class.define_method(:new) do |*args, **kwargs|
      captured_merge_run_id = kwargs[:merge_run_id]
      fake_service
    end

    expected_last_run_at = Time.zone.parse("2026-03-14 10:15:00")

    Merging::SyncImportedEventsJob.perform_now(last_run_at: expected_last_run_at)

    run = ImportRun.where(source_type: "merge").order(:created_at).last
    assert_equal run.id, captured_merge_run_id
    assert_equal expected_last_run_at.to_i, run.metadata.fetch("last_run_at").to_time.to_i
  ensure
    sync_class.alias_method :new, :__original_new_for_test
    sync_class.remove_method :__original_new_for_test
  end

  test "persists merge progress while the job is still running" do
    observed_run_state = {}
    fake_result = Merging::SyncFromImports::Result.new(
      import_records_count: 12,
      groups_count: 4,
      events_created_count: 2,
      events_updated_count: 1,
      duplicate_matches_count: 1,
      offers_upserted_count: 7
    )

    sync_class = Merging::SyncFromImports.singleton_class
    sync_class.alias_method :__original_new_for_test, :new
    sync_class.define_method(:new) do |*args, **kwargs|
      progress_callback = kwargs.fetch(:progress_callback)
      merge_run_id = kwargs.fetch(:merge_run_id)

      Class.new do
        define_method(:call) do
          progress_callback.call(
            import_records_count: 12,
            groups_count: 4,
            events_created_count: 2,
            events_updated_count: 1,
            duplicate_matches_count: 1,
            offers_upserted_count: 7,
            processed_groups_count: 3
          )

          observed_run_state[:value] = ImportRun.find(merge_run_id)
          fake_result
        end
      end.new
    end

    Merging::SyncImportedEventsJob.perform_now(last_run_at: Time.zone.parse("2026-03-14 10:15:00"))

    observed_run_state = observed_run_state.fetch(:value)

    assert_equal 12, observed_run_state.fetched_count
    assert_equal 3, observed_run_state.imported_count
    assert_equal 7, observed_run_state.upserted_count
    assert_equal 12, observed_run_state.metadata["import_records_count"]
    assert_equal 4, observed_run_state.metadata["groups_count"]
    assert_equal 2, observed_run_state.metadata["events_created_count"]
    assert_equal 1, observed_run_state.metadata["events_updated_count"]
    assert_equal 1, observed_run_state.metadata["duplicate_matches_count"]
    assert_equal 3, observed_run_state.metadata["processed_groups_count"]
  ensure
    sync_class.alias_method :new, :__original_new_for_test
    sync_class.remove_method :__original_new_for_test
  end
end
