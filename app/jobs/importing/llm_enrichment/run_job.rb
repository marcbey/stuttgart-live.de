module Importing
  module LlmEnrichment
    class RunJob < ApplicationJob
      queue_as :imports_llm_enrichment

      def perform(import_run_id)
        run = ImportRun.find(import_run_id)
        run = claim_run(run)
        return if run.blank?

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
            upserted_count: result.api_calls_completed_count,
            failed_count: 0,
            metadata: run.metadata.merge(
              "merge_run_id" => result.merge_run_id,
              "events_selected_count" => result.selected_count,
              "events_skipped_count" => result.skipped_count,
              "events_enriched_count" => result.enriched_count,
              "api_calls_count" => result.api_calls_count,
              "api_calls_completed_count" => result.api_calls_completed_count,
              "model" => result.model,
              "web_search_provider" => result.web_search_provider,
              "links_checked_count" => result.links_checked_count,
              "links_rejected_count" => result.links_rejected_count,
              "links_unverifiable_count" => result.links_unverifiable_count,
              "web_search_request_count" => result.web_search_request_count,
              "web_search_candidate_count" => result.web_search_candidate_count,
              "links_found_via_web_search_count" => result.links_found_via_web_search_count,
              "links_null_after_link_lookup_count" => result.links_null_after_link_lookup_count,
              "stop_released_at" => Time.current.iso8601,
              "stop_release_reason" => "Stopped by user"
            )
          )
          return
        end

        logger.info(
          "[LlmEnrichmentRunJob] run_id=#{run.id} succeeded selected=#{result.selected_count} " \
          "enriched=#{result.enriched_count} api_calls=#{result.api_calls_count}"
        )
        run.update!(
          status: "succeeded",
          finished_at: Time.current,
          fetched_count: result.selected_count,
          filtered_count: result.skipped_count,
          imported_count: result.enriched_count,
          upserted_count: result.api_calls_completed_count,
          failed_count: 0,
          metadata: run.metadata.merge(
            "merge_run_id" => result.merge_run_id,
            "events_selected_count" => result.selected_count,
            "events_skipped_count" => result.skipped_count,
            "events_enriched_count" => result.enriched_count,
            "api_calls_count" => result.api_calls_count,
            "api_calls_completed_count" => result.api_calls_completed_count,
            "model" => result.model,
            "web_search_provider" => result.web_search_provider,
            "links_checked_count" => result.links_checked_count,
            "links_rejected_count" => result.links_rejected_count,
            "links_unverifiable_count" => result.links_unverifiable_count,
            "web_search_request_count" => result.web_search_request_count,
            "web_search_candidate_count" => result.web_search_candidate_count,
            "links_found_via_web_search_count" => result.links_found_via_web_search_count,
            "links_null_after_link_lookup_count" => result.links_null_after_link_lookup_count
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
        dispatch_next_queued_run(run)
      end

      private

      def logger
        @logger ||= Importing::Logging.logger
      end

      def claim_run(run)
        run_dispatcher.claim_run!(
          source_type: "llm_enrichment",
          import_source: run.import_source,
          run_id: run.id
        )
      end

      def dispatch_next_queued_run(run)
        return unless run&.persisted?
        return unless %w[succeeded failed canceled].include?(run.reload.status)

        run_dispatcher.dispatch_next(
          source_type: "llm_enrichment",
          import_source: run.import_source
        )
      end

      def run_dispatcher
        @run_dispatcher ||= Backend::ImportSources::RunDispatcher.new(
          registry: Backend::ImportSources::ImporterRegistry.new
        )
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
