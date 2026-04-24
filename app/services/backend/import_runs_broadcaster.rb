module Backend
  class ImportRunsBroadcaster
    STREAM = [ :backend, :import_runs ].freeze
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
      state = Backend::ImportSources::OverviewState.new(recent_runs: recent_runs)

      Turbo::StreamsChannel.broadcast_replace_to(
        STREAM,
        target: "import-runs-live-shell",
        partial: "backend/import_sources/live_shell",
        locals: {
          sections: state.sections,
          active_section_key: state.class::DEFAULT_SECTION,
          overview_state: state,
          import_sources: state.import_sources
        }
      )

      broadcast_single_event_llm_controls!(recent_runs + single_event_llm_runs_for_controls)
    end

    def self.recent_runs_for_list
      RUN_SOURCE_TYPE_BLOCKS.values.flat_map do |source_types|
        ImportRun.where(source_type: source_types).recent.limit(RECENT_RUNS_LIMIT_PER_BLOCK).to_a
      end
    end

    def self.single_event_llm_runs_for_controls
      ImportRun
        .where(source_type: "llm_enrichment")
        .where("metadata @> ?", { trigger_scope: "single_event" }.to_json)
        .where("status IN (:active_statuses) OR updated_at >= :recently_updated_at",
               active_statuses: %w[queued running],
               recently_updated_at: 2.minutes.ago)
        .to_a
    end

    def self.broadcast_single_event_llm_controls!(runs)
      single_event_llm_event_ids(runs).each do |event_id|
        event = Event.find_by(id: event_id)
        next if event.blank?

        Turbo::StreamsChannel.broadcast_replace_to(
          [ :backend, :event_llm_enrichment, event.id ],
          target: ActionView::RecordIdentifier.dom_id(event, :llm_enrichment_run_controls),
          partial: "backend/events/llm_enrichment_run_controls",
          locals: {
            event: event,
            filter_status: event.status
          }
        )
      end
    end

    def self.single_event_llm_event_ids(runs)
      runs.filter_map do |run|
        next unless run.source_type == "llm_enrichment"

        metadata = run.metadata.is_a?(Hash) ? run.metadata.deep_stringify_keys : {}
        next unless metadata["trigger_scope"] == "single_event"

        Integer(metadata["target_event_id"], exception: false)
      end.uniq
    end
  end
end
