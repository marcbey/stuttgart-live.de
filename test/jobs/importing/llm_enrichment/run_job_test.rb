require "test_helper"

module Importing
  module LlmEnrichment
    class RunJobTest < ActiveJob::TestCase
      test "keeps a force-canceled run canceled when a later importer error arrives" do
        source = import_sources(:two)
        run = source.import_runs.create!(
          source_type: "llm_enrichment",
          status: "queued",
          started_at: 1.minute.ago,
          metadata: {
            "trigger_scope" => "single_event",
            "target_event_id" => events(:published_one).id
          }
        )

        importer_class = Importing::LlmEnrichment::Importer
        original_new = importer_class.method(:new)
        importer_class.define_singleton_method(:new) do |run:, **|
          Struct.new(:run) do
            def call
              run.update!(
                status: "canceled",
                finished_at: Time.current,
                metadata: run.metadata.merge(
                  "stop_requested" => true,
                  "stop_requested_at" => Time.current.iso8601,
                  "stop_released_at" => Time.current.iso8601,
                  "stop_release_reason" => "Force-stopped single-event run"
                )
              )
              raise OpenAi::ResponsesClient::Error, "timeout"
            end
          end.new(run)
        end

        Importing::LlmEnrichment::RunJob.perform_now(run.id)

        run.reload
        assert_equal "canceled", run.status
        assert_equal "Force-stopped single-event run", run.metadata["stop_release_reason"]
        assert_nil run.error_message
      ensure
        importer_class.define_singleton_method(:new, original_new)
      end
    end
  end
end
