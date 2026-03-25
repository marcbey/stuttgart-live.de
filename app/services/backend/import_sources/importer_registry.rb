module Backend
  module ImportSources
    class ImporterRegistry
      CONFIG = {
        "easyticket" => {
          label: "Easyticket",
          started_notice: "Easyticket-Import wurde gestartet.",
          run_job_class: Importing::Easyticket::RunJob,
          importer_class: Importing::Easyticket::Importer,
          stop_route_helper: :stop_easyticket_run_backend_import_source_path,
          run_mode: :exclusive,
          max_retries: Importing::RetryPolicy::RETRY_DELAYS.size,
          run_job_arguments_builder: ->(import_source, run) { [ import_source.id, run.id ] },
          run_source_resolver: -> { ImportSource.ensure_easyticket_source! }
        },
        "eventim" => {
          label: "Eventim",
          started_notice: "Eventim-Import wurde gestartet.",
          run_job_class: Importing::Eventim::RunJob,
          importer_class: Importing::Eventim::Importer,
          stop_route_helper: :stop_eventim_run_backend_import_source_path,
          run_mode: :exclusive,
          max_retries: Importing::RetryPolicy::RETRY_DELAYS.size,
          run_job_arguments_builder: ->(import_source, run) { [ import_source.id, run.id ] },
          run_source_resolver: -> { ImportSource.find_by(source_type: "eventim") || ImportSource.ensure_eventim_source! }
        },
        "reservix" => {
          label: "Reservix",
          started_notice: "Reservix-Import wurde gestartet.",
          run_job_class: Importing::Reservix::RunJob,
          importer_class: Importing::Reservix::Importer,
          stop_route_helper: :stop_reservix_run_backend_import_source_path,
          run_mode: :exclusive,
          max_retries: Importing::RetryPolicy::RETRY_DELAYS.size,
          run_job_arguments_builder: ->(import_source, run) { [ import_source.id, run.id ] },
          run_source_resolver: -> { ImportSource.ensure_reservix_source! }
        },
        "merge" => {
          label: "Merge",
          importer_class: Merging::SyncImportedEventsJob,
          stop_route_helper: :stop_merge_run_backend_import_sources_path,
          run_mode: :exclusive,
          max_retries: 0,
          run_source_resolver: lambda {
            ImportSource.find_by(source_type: "eventim") ||
              ImportSource.find_by(source_type: "easyticket") ||
              ImportSource.ensure_eventim_source!
          }
        },
        "llm_enrichment" => {
          label: "LLM-Enrichment",
          started_notice: "LLM-Enrichment wurde gestartet.",
          run_job_class: Importing::LlmEnrichment::RunJob,
          importer_class: Importing::LlmEnrichment::Importer,
          stop_route_helper: :stop_llm_enrichment_run_backend_import_sources_path,
          run_mode: :serial_queue,
          max_retries: 0,
          run_job_arguments_builder: ->(_import_source, run) { [ run.id ] },
          run_source_resolver: lambda {
            ImportSource.find_by(source_type: "eventim") ||
              ImportSource.find_by(source_type: "easyticket") ||
              ImportSource.ensure_eventim_source!
          }
        },
        "llm_genre_grouping" => {
          label: "LLM-Genre-Gruppierung",
          started_notice: "LLM-Genre-Gruppierung wurde gestartet.",
          run_job_class: Importing::LlmGenreGrouping::RunJob,
          importer_class: Importing::LlmGenreGrouping::Importer,
          stop_route_helper: :stop_llm_genre_grouping_run_backend_import_sources_path,
          run_mode: :exclusive,
          max_retries: 0,
          run_job_arguments_builder: ->(_import_source, run) { [ run.id ] },
          already_running_alert_builder: ->(run) { "Ein LLM-Genre-Gruppierungs-Lauf läuft bereits (Run ##{run.id})." },
          stop_requested_notice_builder: ->(run) { "Stop für LLM-Genre-Gruppierung (Run ##{run.id}) wurde angefordert." },
          canceled_queue_notice_builder: ->(run) { "LLM-Genre-Gruppierung (Run ##{run.id}) wurde aus der Warteschlange entfernt." },
          run_source_resolver: lambda {
            ImportSource.find_by(source_type: "eventim") ||
              ImportSource.find_by(source_type: "easyticket") ||
              ImportSource.ensure_eventim_source!
          }
        }
      }.freeze

      def source_types
        CONFIG.keys
      end

      def fetch(source_type, required: true)
        config = CONFIG[source_type.to_s]
        return config if config.present? || !required

        raise KeyError, "key not found: #{source_type.inspect}"
      end

      def resolve_run_source(source_type)
        config = fetch(source_type)
        resolver = config[:run_source_resolver]
        return resolver.call if resolver.respond_to?(:call)

        ImportSource.find_by(source_type: source_type.to_s)
      end
    end
  end
end
