module Backend
  module ImportSources
    class OverviewState
      DEFAULT_SECTION = "raw_importer".freeze

      SECTION_DEFINITIONS = [
        {
          key: "raw_importer",
          label: "Raw Importer",
          panel_id: "import-runs-panel-raw-importer",
          panel_content_id: "import-runs-panel-content-raw-importer",
          tab_id: "import-runs-tab-raw-importer",
          indicator_id: "import-runs-tab-indicator-raw-importer",
          partial: "backend/import_sources/panels/raw_importer"
        },
        {
          key: "merge_importer",
          label: "Merge Importer",
          panel_id: "import-runs-panel-merge-importer",
          panel_content_id: "import-runs-panel-content-merge-importer",
          tab_id: "import-runs-tab-merge-importer",
          indicator_id: "import-runs-tab-indicator-merge-importer",
          partial: "backend/import_sources/panels/merge_importer"
        },
        {
          key: "llm_enrichment",
          label: "LLM-Enrichment",
          panel_id: "import-runs-panel-llm-enrichment",
          panel_content_id: "import-runs-panel-content-llm-enrichment",
          tab_id: "import-runs-tab-llm-enrichment",
          indicator_id: "import-runs-tab-indicator-llm-enrichment",
          partial: "backend/import_sources/panels/llm_enrichment"
        },
        {
          key: "llm_genre_grouping",
          label: "LLM-Genre-Gruppierung",
          panel_id: "import-runs-panel-llm-genre-grouping",
          panel_content_id: "import-runs-panel-content-llm-genre-grouping",
          tab_id: "import-runs-tab-llm-genre-grouping",
          indicator_id: "import-runs-tab-indicator-llm-genre-grouping",
          partial: "backend/import_sources/panels/llm_genre_grouping"
        }
      ].freeze

      RUN_SOURCE_TYPE_BLOCKS = {
        "raw_importer" => %w[easyticket eventim reservix],
        "merge_importer" => %w[merge],
        "llm_enrichment" => %w[llm_enrichment],
        "llm_genre_grouping" => %w[llm_genre_grouping]
      }.freeze

      def initialize(recent_runs: nil, import_sources: nil)
        @recent_runs = Array(recent_runs || Backend::ImportRunsBroadcaster.recent_runs_for_list)
        @import_sources = import_sources || ImportSource.includes(:import_source_config).order(:source_type).to_a
      end

      attr_reader :recent_runs, :import_sources

      def self.normalized_section_key(key)
        raw_key = key.to_s
        RUN_SOURCE_TYPE_BLOCKS.key?(raw_key) ? raw_key : DEFAULT_SECTION
      end

      def sections
        SECTION_DEFINITIONS.map do |definition|
          definition.merge(indicator: indicator_for(definition.fetch(:key)))
        end
      end

      def section(key)
        normalized_key = normalized_section_key(key)
        sections.find { |definition| definition.fetch(:key) == normalized_key }
      end

      def normalized_section_key(key)
        self.class.normalized_section_key(key)
      end

      def runs_for(section_key)
        source_types = RUN_SOURCE_TYPE_BLOCKS.fetch(normalized_section_key(section_key))
        recent_runs.select { |run| source_types.include?(run.source_type.to_s) }
      end

      def merge_sync_needed?
        latest_import_success_at = ImportRun.where(source_type: %w[easyticket reservix eventim], status: "succeeded").maximum(:finished_at)
        return false if latest_import_success_at.blank?

        latest_merge_success_at = ImportRun.where(source_type: "merge", status: "succeeded").maximum(:finished_at)
        latest_merge_success_at.blank? || latest_import_success_at > latest_merge_success_at
      end

      private

      def indicator_for(section_key)
        runs = runs_for(section_key)
        stopping_count = runs.count { |run| run.status == "running" && stop_requested?(run) }
        running_count = runs.count { |run| run.status == "running" && !stop_requested?(run) }

        if stopping_count.positive?
          {
            status: "stopping",
            count: stopping_count,
            label: "Stop angefordert",
            sr_label: "#{stopping_count} laufende Jobs werden gestoppt"
          }
        elsif running_count.positive?
          {
            status: "running",
            count: running_count,
            label: "Läuft",
            sr_label: "#{running_count} laufende Jobs"
          }
        else
          {
            status: "idle",
            count: 0,
            label: nil,
            sr_label: "Keine laufenden Jobs"
          }
        end
      end

      def stop_requested?(run)
        return false unless run.metadata.is_a?(Hash)

        ActiveModel::Type::Boolean.new.cast(run.metadata.deep_stringify_keys["stop_requested"])
      end
    end
  end
end
