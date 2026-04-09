require "test_helper"

class Backend::ImportSources::MergeRunStarterTest < ActiveSupport::TestCase
  setup do
    @registry = Backend::ImportSources::ImporterRegistry.new
    @source = @registry.resolve_run_source("merge")
  end

  test "creates merge run before enqueueing the job" do
    observed_run = nil
    job_class = Class.new do
      class << self
        attr_accessor :callback
      end

      def self.perform_later(import_run_id:)
        self.callback&.call(import_run_id)
        Struct.new(:job_id, :provider_job_id).new("job-123", 456)
      end
    end

    job_class.callback = lambda do |import_run_id|
      observed_run = ImportRun.find(import_run_id)
    end

    result = Backend::ImportSources::MergeRunStarter.new(
      registry: @registry,
      job_class: job_class
    ).call

    assert_equal "Merge-Sync wurde gestartet.", result.notice
    assert_nil result.alert
    assert_equal result.run.id, observed_run.id
    assert_equal "running", observed_run.status
    assert_equal "job-123", result.run.reload.metadata["job_id"]
    assert_equal 456, result.run.metadata["provider_job_id"]
  end

  test "marks merge run failed when enqueueing the job raises" do
    failing_job_class = Class.new do
      def self.perform_later(import_run_id:)
        raise "queue unavailable for run #{import_run_id}"
      end
    end

    error = assert_raises RuntimeError do
      Backend::ImportSources::MergeRunStarter.new(
        registry: @registry,
        job_class: failing_job_class
      ).call
    end

    assert_includes error.message, "queue unavailable"

    run = ImportRun.where(source_type: "merge").order(:created_at).last
    assert_equal "failed", run.status
    assert run.finished_at.present?
    assert_includes run.error_message, "Merge-Sync konnte nicht an die Queue übergeben werden"
  end
end
