module Backend
  module ImportSources
    class ImporterRegistry
      CONFIG = {
        "easyticket" => {
          label: "Easyticket",
          run_job_class: Importing::Easyticket::RunJob,
          importer_class: Importing::Easyticket::Importer,
          stop_route_helper: :stop_easyticket_run_backend_import_source_path
        },
        "eventim" => {
          label: "Eventim",
          run_job_class: Importing::Eventim::RunJob,
          importer_class: Importing::Eventim::Importer,
          stop_route_helper: :stop_eventim_run_backend_import_source_path
        },
        "reservix" => {
          label: "Reservix",
          run_job_class: Importing::Reservix::RunJob,
          importer_class: Importing::Reservix::Importer,
          stop_route_helper: :stop_reservix_run_backend_import_source_path
        },
        "llm_enrichment" => {
          label: "LLM Enrichment",
          run_job_class: Importing::LlmEnrichment::RunJob,
          importer_class: Importing::LlmEnrichment::Importer,
          stop_route_helper: :stop_llm_enrichment_run_backend_import_sources_path
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
    end
  end
end
