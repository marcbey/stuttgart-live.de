require "test_helper"

class Importing::Easyticket::RunJobTest < ActiveJob::TestCase
  setup do
    clear_enqueued_jobs
    clear_performed_jobs
    @source = import_sources(:one)
  end

  test "uses easyticket queue" do
    assert_equal "imports_easyticket", Importing::Easyticket::RunJob.queue_name
  end

  test "retries transient request failures after 30 seconds" do
    failing_importer = Class.new do
      def call
        raise Importing::Easyticket::RequestError, "temporary upstream failure"
      end
    end.new

    with_stubbed_constructor(Importing::Easyticket::Importer, failing_importer) do
      Importing::Easyticket::RunJob.perform_now(@source.id)
    end

    retry_job = enqueued_jobs.last
    assert_equal Importing::Easyticket::RunJob, retry_job[:job]
    assert_in_delta 30.seconds, retry_job[:at] - Time.current.to_f, 2.0
  end

  test "does not retry non transient failures" do
    failing_importer = Class.new do
      def call
        raise ArgumentError, "invalid payload"
      end
    end.new

    with_stubbed_constructor(Importing::Easyticket::Importer, failing_importer) do
      assert_raises(ArgumentError) do
        Importing::Easyticket::RunJob.perform_now(@source.id)
      end
    end

    assert_equal 0, enqueued_jobs.size
  end

  private

  def with_stubbed_constructor(klass, instance)
    singleton = klass.singleton_class
    singleton.alias_method :__original_new_for_test, :new
    singleton.define_method(:new) { |*| instance }

    yield
  ensure
    singleton.alias_method :new, :__original_new_for_test
    singleton.remove_method :__original_new_for_test
  end
end
