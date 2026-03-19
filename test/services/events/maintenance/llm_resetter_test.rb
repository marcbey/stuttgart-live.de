require "test_helper"

class Events::Maintenance::LlmResetterTest < ActiveSupport::TestCase
  FakeQueueConnection = Struct.new(:available_tables) do
    def data_source_exists?(table_name)
      available_tables.include?(table_name)
    end
  end

  FakeQueuePool = Struct.new(:connection) do
    def with_connection
      yield connection
    end
  end

  class FakeQueueRecord
    class << self
      attr_accessor :available_tables

      def transaction
        yield
      end

      def connection_pool
        FakeQueuePool.new(FakeQueueConnection.new(Array(available_tables)))
      end
    end
  end

  class FakeQueueRelation
    def initialize(model, filters)
      @model = model
      @filters = filters
    end

    def count
      filtered_records.count
    end

    def delete_all
      remaining_records = model.records.reject { |record| matches?(record) }
      deleted_count = model.records.count - remaining_records.count
      model.records = remaining_records
      deleted_count
    end

    def select(field_name)
      filtered_records.map { |record| record.fetch(field_name) }
    end

    private

    attr_reader :filters, :model

    def filtered_records
      model.records.select { |record| matches?(record) }
    end

    def matches?(record)
      filters.all? do |key, expected|
        values = expected.is_a?(Array) ? expected : [ expected ]
        values.include?(record[key])
      end
    end
  end

  class FakeQueueModel
    class << self
      attr_accessor :records

      def where(filters)
        FakeQueueRelation.new(self, filters)
      end

      def count
        records.count
      end
    end
  end

  class FakeJobModel < FakeQueueModel
    def self.table_name = "solid_queue_jobs"
  end

  class FakeReadyExecutionModel < FakeQueueModel
    def self.table_name = "solid_queue_ready_executions"
  end

  class FakeScheduledExecutionModel < FakeQueueModel
    def self.table_name = "solid_queue_scheduled_executions"
  end

  setup do
    @llm_run = ImportRun.create!(
      import_source: import_sources(:one),
      source_type: "llm_enrichment",
      status: "running",
      started_at: Time.current,
      metadata: {}
    )
    @other_run = ImportRun.create!(
      import_source: import_sources(:one),
      source_type: "merge",
      status: "running",
      started_at: Time.current,
      metadata: {}
    )

    EventLlmEnrichment.create!(
      event: events(:published_one),
      source_run: @llm_run,
      genre: [ "Jazz" ],
      venue: events(:published_one).venue,
      artist_description: "Beschreibung",
      event_description: "Event-Beschreibung",
      venue_description: "Venue-Beschreibung",
      model: "gpt-5-mini",
      prompt_version: "v1",
      raw_response: {}
    )

    @llm_run.import_run_errors.create!(
      source_type: "llm_enrichment",
      message: "LLM Fehler",
      error_class: "RuntimeError",
      payload: {}
    )
    @other_run.import_run_errors.create!(
      source_type: "merge",
      message: "Anderer Fehler",
      error_class: "RuntimeError",
      payload: {}
    )

    FakeJobModel.records = [
      { id: 1, class_name: "Importing::LlmEnrichment::RunJob" },
      { id: 2, class_name: "Importing::Eventim::RunJob" }
    ]
    FakeReadyExecutionModel.records = [
      { id: 1, job_id: 1 },
      { id: 2, job_id: 2 }
    ]
    FakeScheduledExecutionModel.records = [
      { id: 1, job_id: 1 }
    ]
    FakeQueueRecord.available_tables = [
      "solid_queue_ready_executions",
      "solid_queue_scheduled_executions"
    ]
  end

  test "resets llm enrichments, llm runs, llm errors, and queued llm jobs only" do
    result = Events::Maintenance::LlmResetter.call(
      solid_queue_available: true,
      solid_queue_job_model: FakeJobModel,
      solid_queue_execution_models: [
        [ "solid_queue_ready_executions", FakeReadyExecutionModel ],
        [ "solid_queue_scheduled_executions", FakeScheduledExecutionModel ]
      ],
      solid_queue_record_class: FakeQueueRecord
    )

    assert_equal 0, EventLlmEnrichment.count
    assert_equal 0, ImportRun.where(source_type: "llm_enrichment").count
    assert_equal 0, ImportRunError.where(import_run_id: @llm_run.id).count
    assert_equal 1, ImportRun.where(id: @other_run.id).count
    assert_equal 1, ImportRunError.where(import_run_id: @other_run.id).count

    assert_equal [ { id: 2, class_name: "Importing::Eventim::RunJob" } ], FakeJobModel.records
    assert_equal [ { id: 2, job_id: 2 } ], FakeReadyExecutionModel.records
    assert_empty FakeScheduledExecutionModel.records

    assert_equal :cleared, result.queue_status
    assert_equal 0, result.event_counts.fetch("event_llm_enrichments")
    assert_equal 0, result.import_counts.fetch("llm_import_runs")
    assert_equal 0, result.import_counts.fetch("llm_import_run_errors")
    assert_equal 0, result.queue_counts.fetch("solid_queue_jobs")
    assert_equal 0, result.queue_counts.fetch("solid_queue_ready_executions")
    assert_equal 0, result.queue_counts.fetch("solid_queue_scheduled_executions")
  end

  test "skips queue cleanup when solid queue is unavailable" do
    result = Events::Maintenance::LlmResetter.call(
      solid_queue_available: false,
      solid_queue_job_model: FakeJobModel,
      solid_queue_execution_models: [
        [ "solid_queue_ready_executions", FakeReadyExecutionModel ]
      ],
      solid_queue_record_class: FakeQueueRecord
    )

    assert_equal :skipped, result.queue_status
    assert_empty result.queue_counts
    assert_equal 0, EventLlmEnrichment.count
    assert_equal 0, ImportRun.where(source_type: "llm_enrichment").count
    assert_equal 2, FakeJobModel.records.count
    assert_equal 2, FakeReadyExecutionModel.records.count
  end
end
