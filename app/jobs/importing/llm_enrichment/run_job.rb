module Importing
  module LlmEnrichment
    class RunJob < ApplicationJob
      queue_as :imports_llm_enrichment

      def perform(import_run_id)
        run = ImportRun.find(import_run_id)
        logger.info("[LlmEnrichmentRunJob] run_id=#{run.id} perform started")
        importer = Importing::LlmEnrichment::Importer.new(run: run)
        result = importer.call

        if result.canceled
          logger.info("[LlmEnrichmentRunJob] run_id=#{run.id} canceled selected=#{result.selected_count} enriched=#{result.enriched_count}")
          run.update!(
            status: "canceled",
            finished_at: Time.current,
            fetched_count: result.selected_count,
            filtered_count: result.skipped_count,
            imported_count: result.enriched_count,
            upserted_count: run.upserted_count,
            failed_count: 0,
            metadata: run.metadata.merge(
              "merge_run_id" => result.merge_run_id,
              "events_selected_count" => result.selected_count,
              "events_skipped_count" => result.skipped_count,
              "events_enriched_count" => result.enriched_count,
              "batches_count" => result.batches_count,
              "batch_size" => Importing::LlmEnrichment::Importer::BATCH_SIZE,
              "model" => result.model,
              "stop_released_at" => Time.current.iso8601,
              "stop_release_reason" => "Stopped by user"
            )
          )
          return
        end

        logger.info("[LlmEnrichmentRunJob] run_id=#{run.id} succeeded selected=#{result.selected_count} enriched=#{result.enriched_count} batches=#{result.batches_count}")
        run.update!(
          status: "succeeded",
          finished_at: Time.current,
          fetched_count: result.selected_count,
          filtered_count: result.skipped_count,
          imported_count: result.enriched_count,
          upserted_count: result.batches_count,
          failed_count: 0,
          metadata: run.metadata.merge(
            "merge_run_id" => result.merge_run_id,
            "events_selected_count" => result.selected_count,
            "events_skipped_count" => result.skipped_count,
            "events_enriched_count" => result.enriched_count,
            "batches_count" => result.batches_count,
            "batch_size" => Importing::LlmEnrichment::Importer::BATCH_SIZE,
            "model" => result.model
          )
        )
      rescue StandardError => e
        logger.error("[LlmEnrichmentRunJob] run_id=#{run&.id} failed: #{e.class}: #{e.message}")
        run&.update!(
          status: "failed",
          finished_at: Time.current,
          error_message: e.message
        )
        create_import_run_error!(run: run, error: e)
        raise
      ensure
        Backend::ImportRunsBroadcaster.broadcast!
      end

      private

      def logger
        @logger ||= Importing::Logging.logger
      end

      def create_import_run_error!(run:, error:)
        return unless run&.persisted?

        run.import_run_errors.create!(
          source_type: "llm_enrichment",
          error_class: error.class.to_s,
          message: error.message.to_s.presence || error.class.to_s,
          payload: {}
        )
      rescue StandardError
        nil
      end
    end
  end
end
