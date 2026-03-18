module Backend
  class ImportRunsBroadcaster
    STREAM = [ :backend, :import_runs ].freeze
    TARGET = "import-runs-table".freeze
    LISTED_SOURCE_TYPES = %w[easyticket eventim reservix merge llm_enrichment].freeze
    RECENT_RUNS_LIMIT = 10

    def self.broadcast!
      recent_runs = ImportRun.where(source_type: LISTED_SOURCE_TYPES).recent.limit(RECENT_RUNS_LIMIT)

      Turbo::StreamsChannel.broadcast_replace_to(
        STREAM,
        target: TARGET,
        partial: "backend/import_sources/recent_runs_table",
        locals: { recent_runs: recent_runs }
      )
    end
  end
end
