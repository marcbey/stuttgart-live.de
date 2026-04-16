module Importing
  module LlmEnrichment
    class DailyRunJob < ApplicationJob
      queue_as :default

      def perform
        ImportSource.ensure_supported_sources!

        registry = Backend::ImportSources::ImporterRegistry.new
        import_source = registry.resolve_run_source("llm_enrichment")

        Backend::ImportSources::RunEnqueuer.new(
          registry: registry,
          maintenance: Backend::ImportSources::RunMaintenance.new(registry: registry),
          dispatcher: Backend::ImportSources::RunDispatcher.new(registry: registry)
        ).call(
          source_type: "llm_enrichment",
          import_source: import_source,
          run_metadata: {
            "triggered_by" => "scheduler",
            "schedule_name" => "daily_llm_enrichment_run",
            "refresh_existing" => false,
            "refresh_links_only" => false
          }
        )
      end
    end
  end
end
