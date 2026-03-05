module Importing
  module Easyticket
    class RunJob < ApplicationJob
      queue_as :imports_easyticket
      RETRIABLE_ERRORS = (Importing::RetryPolicy::TRANSIENT_ERRORS + [ Importing::Easyticket::RequestError ]).freeze

      retry_on(
        *RETRIABLE_ERRORS,
        wait: ->(executions) { Importing::RetryPolicy.delay_for(executions) },
        attempts: Importing::RetryPolicy::RETRY_ATTEMPTS
      )

      def perform(import_source_id = nil)
        source =
          if import_source_id.present?
            ImportSource.find(import_source_id)
          else
            ImportSource.ensure_easyticket_source!
          end

        run = Importing::Easyticket::Importer.new(
          import_source: source,
          run_metadata: run_metadata_for_execution
        ).call
        run
      end

      private

      def run_metadata_for_execution
        attempt = executions.to_i
        attempt = 1 if attempt < 1

        {
          "job_id" => job_id,
          "provider_job_id" => provider_job_id,
          "job_attempt" => attempt,
          "job_retries_used" => [ attempt - 1, 0 ].max,
          "max_retries" => Importing::RetryPolicy::RETRY_DELAYS.size
        }
      end
    end
  end
end
