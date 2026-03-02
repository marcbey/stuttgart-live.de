module Backend
  class EasyticketImportRunsBroadcaster
    STREAM = [ :backend, :easyticket_import_runs ].freeze
    TARGET = "easyticket-import-runs-table".freeze

    def self.broadcast!
      recent_runs = ImportRun.where(source_type: "easyticket").recent.limit(10)

      Turbo::StreamsChannel.broadcast_replace_to(
        STREAM,
        target: TARGET,
        partial: "backend/import_sources/recent_runs_table",
        locals: { recent_runs: recent_runs }
      )
    end
  end
end
