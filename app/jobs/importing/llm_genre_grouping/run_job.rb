module Importing
  module LlmGenreGrouping
    class RunJob < ApplicationJob
      queue_as :imports_llm_genre_grouping

      def perform(import_run_id)
        run = ImportRun.find(import_run_id)
        logger.info("[LlmGenreGroupingRunJob] run_id=#{run.id} perform started")
        importer = Importing::LlmGenreGrouping::Importer.new(run: run)
        result = importer.call

        if result.canceled
          logger.info("[LlmGenreGroupingRunJob] run_id=#{run.id} canceled selected=#{result.selected_count} requests=#{result.requests_count}")
          run.update!(
            status: "canceled",
            finished_at: Time.current,
            fetched_count: result.selected_count,
            filtered_count: result.skipped_count,
            imported_count: result.groups_count,
            upserted_count: result.requests_count,
            failed_count: 0,
            metadata: run.metadata.merge(
              "genres_selected_count" => result.selected_count,
              "genres_skipped_count" => result.skipped_count,
              "groups_created_count" => result.groups_count,
              "requests_count" => result.requests_count,
              "requested_group_count" => result.requested_group_count,
              "effective_group_count" => result.effective_group_count,
              "snapshot_id" => result.snapshot_id,
              "snapshot_key" => result.snapshot_key,
              "model" => result.model,
              "stop_released_at" => Time.current.iso8601,
              "stop_release_reason" => "Stopped by user"
            )
          )
          return
        end

        logger.info("[LlmGenreGroupingRunJob] run_id=#{run.id} succeeded groups=#{result.groups_count} requests=#{result.requests_count} snapshot_id=#{result.snapshot_id}")
        run.update!(
          status: "succeeded",
          finished_at: Time.current,
          fetched_count: result.selected_count,
          filtered_count: result.skipped_count,
          imported_count: result.groups_count,
          upserted_count: result.requests_count,
          failed_count: 0,
          metadata: run.metadata.merge(
            "genres_selected_count" => result.selected_count,
            "genres_skipped_count" => result.skipped_count,
            "groups_created_count" => result.groups_count,
            "requests_count" => result.requests_count,
            "requested_group_count" => result.requested_group_count,
            "effective_group_count" => result.effective_group_count,
            "snapshot_id" => result.snapshot_id,
            "snapshot_key" => result.snapshot_key,
            "model" => result.model
          )
        )
      rescue StandardError => e
        logger.error("[LlmGenreGroupingRunJob] run_id=#{run&.id} failed: #{e.class}: #{e.message}")
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
          source_type: "llm_genre_grouping",
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
