require "test_helper"

class Importing::Eventim::RunJobTest < ActiveJob::TestCase
  setup do
    clear_enqueued_jobs
    clear_performed_jobs
    @source = import_sources(:two)
  end

  test "uses eventim queue" do
    assert_equal "imports_eventim", Importing::Eventim::RunJob.queue_name
  end

  test "retries transient request failures after 30 seconds" do
    failing_importer = Class.new do
      def call
        raise Importing::Eventim::RequestError, "temporary feed outage"
      end
    end.new

    with_stubbed_constructor(Importing::Eventim::Importer, failing_importer) do
      Importing::Eventim::RunJob.perform_now(@source.id)
    end

    retry_job = enqueued_jobs.last
    assert_equal Importing::Eventim::RunJob, retry_job[:job]
    assert_in_delta 30.seconds, retry_job[:at] - Time.current.to_f, 2.0
  end

  test "does not retry non transient failures" do
    failing_importer = Class.new do
      def call
        raise ArgumentError, "invalid xml"
      end
    end.new

    with_stubbed_constructor(Importing::Eventim::Importer, failing_importer) do
      assert_raises(ArgumentError) do
        Importing::Eventim::RunJob.perform_now(@source.id)
      end
    end

    assert_equal 0, enqueued_jobs.size
  end

  test "passes retry metadata to importer run" do
    captured_metadata = nil
    fake_run = Struct.new(:status).new("failed")

    with_stubbed_constructor(Importing::Eventim::Importer, nil) do |singleton|
      singleton.define_method(:new) do |*args, **kwargs|
        captured_metadata = kwargs[:run_metadata]
        Struct.new(:call).new(fake_run)
      end

      Importing::Eventim::RunJob.perform_now(@source.id)
    end

    assert_equal 1, captured_metadata["job_attempt"]
    assert_equal 0, captured_metadata["job_retries_used"]
    assert_equal 3, captured_metadata["max_retries"]
    assert captured_metadata["job_id"].present?
  end

  test "does not enqueue merge job automatically after successful import" do
    successful_run = Struct.new(:status).new("succeeded")

    with_stubbed_constructor(Importing::Eventim::Importer, Struct.new(:call).new(successful_run)) do
      assert_no_enqueued_jobs do
        Importing::Eventim::RunJob.perform_now(@source.id)
      end
    end
  end

  private

  def with_stubbed_constructor(klass, instance = nil)
    singleton = klass.singleton_class
    singleton.alias_method :__original_new_for_test, :new
    singleton.define_method(:new) { |*| instance } if instance

    yield singleton
  ensure
    singleton.alias_method :new, :__original_new_for_test
    singleton.remove_method :__original_new_for_test
  end
end
