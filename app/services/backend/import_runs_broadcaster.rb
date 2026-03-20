module Backend
  class ImportRunsBroadcaster
    STREAM = [ :backend, :import_runs ].freeze
    TARGET = "import-runs-table".freeze
    LISTED_SOURCE_TYPES = %w[easyticket eventim reservix merge llm_enrichment llm_genre_grouping].freeze
    RECENT_RUNS_LIMIT_PER_BLOCK = 10
    RUN_SOURCE_TYPE_BLOCKS = {
      raw: %w[easyticket eventim reservix],
      merge: %w[merge],
      llm_enrichment: %w[llm_enrichment],
      llm_genre_grouping: %w[llm_genre_grouping]
    }.freeze

    def self.broadcast!
      recent_runs = recent_runs_for_list

      Turbo::StreamsChannel.broadcast_replace_to(
        STREAM,
        target: TARGET,
        partial: "backend/import_sources/recent_runs_table",
        locals: { recent_runs: recent_runs }
      )
    end

    def self.recent_runs_for_list
      RUN_SOURCE_TYPE_BLOCKS.values.flat_map do |source_types|
        ImportRun.where(source_type: source_types).recent.limit(RECENT_RUNS_LIMIT_PER_BLOCK).to_a
      end
    end
  end
end
