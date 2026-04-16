module Events
  module Maintenance
    class LlmLinkBackfillEnqueuer
      DEFAULT_CHUNK_SIZE = 250
      DEFAULT_STATUSES = %w[published ready_for_publish needs_review].freeze

      Result = Data.define(:eligible_count, :runs_enqueued, :chunk_size, :statuses)

      def self.call(...)
        new.call(...)
      end

      def initialize(
        chunk_size: DEFAULT_CHUNK_SIZE,
        statuses: DEFAULT_STATUSES,
        clock: -> { Time.current },
        importer_registry: Backend::ImportSources::ImporterRegistry.new,
        run_dispatcher: nil,
        run_maintenance: nil,
        run_enqueuer: nil
      )
        @chunk_size = [ chunk_size.to_i, 1 ].max
        @statuses = Array(statuses).map(&:to_s).map(&:strip).reject(&:blank?).uniq
        @clock = clock
        @importer_registry = importer_registry
        @run_dispatcher = run_dispatcher
        @run_maintenance = run_maintenance
        @run_enqueuer = run_enqueuer
      end

      def call
        event_ids = eligible_scope.pluck(:id)

        event_ids.each_slice(chunk_size) do |ids|
          run_enqueuer.call(
            source_type: "llm_enrichment",
            import_source: import_source,
            run_metadata: {
              "triggered_at" => clock.call.iso8601,
              "triggered_by" => "maintenance_task",
              "refresh_existing" => true,
              "refresh_links_only" => true,
              "target_event_ids" => ids
            }
          )
        end

        Result.new(
          eligible_count: event_ids.size,
          runs_enqueued: event_ids.each_slice(chunk_size).count,
          chunk_size: chunk_size,
          statuses: statuses
        )
      end

      private

      attr_reader :chunk_size, :clock, :importer_registry, :run_dispatcher, :run_enqueuer, :run_maintenance, :statuses

      def import_source
        @import_source ||= importer_registry.resolve_run_source("llm_enrichment")
      end

      def eligible_scope
        Event
          .joins(:llm_enrichment)
          .where(status: statuses)
          .where("events.start_at >= ?", clock.call)
          .order(Arel.sql(status_order_sql), :start_at, :id)
      end

      def status_order_sql
        statuses.each_with_index.map do |status, index|
          "WHEN #{ActiveRecord::Base.connection.quote(status)} THEN #{index}"
        end.then { |conditions| "CASE events.status #{conditions.join(' ')} ELSE #{statuses.length} END" }
      end

      def run_enqueuer
        @run_enqueuer ||=
          Backend::ImportSources::RunEnqueuer.new(
            registry: importer_registry,
            maintenance: run_maintenance_instance,
            dispatcher: run_dispatcher_instance
          )
      end

      def run_dispatcher_instance
        @run_dispatcher ||= Backend::ImportSources::RunDispatcher.new(registry: importer_registry)
      end

      def run_maintenance_instance
        @run_maintenance ||= Backend::ImportSources::RunMaintenance.new(registry: importer_registry)
      end
    end
  end
end
