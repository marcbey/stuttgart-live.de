module Events
  module Publication
    class PublishScheduledEvents
      Result = Data.define(:processed_count, :published_count, :skipped_count)

      BATCH_SIZE = 100

      def self.call(...)
        new(...).call
      end

      def initialize(scope: Event.all, batch_size: BATCH_SIZE, logger: Rails.logger, now: Time.current)
        @scope = scope
        @batch_size = batch_size
        @logger = logger
        @now = normalize_now(now)
      end

      def call
        processed_count = 0
        published_count = 0
        skipped_count = 0

        due_events.find_each(batch_size: batch_size) do |event|
          processed_count += 1

          completeness = Editorial::EventCompletenessChecker.new(event: event).call
          event.completeness_score = completeness.score
          event.completeness_flags = completeness.flags

          unless completeness.ready_for_publish?
            persist_completeness!(event) if event.changed?
            skipped_count += 1
            next
          end

          event.publish!(user: nil, auto_published: true)
          Editorial::EventChangeLogger.log!(event: event, action: "scheduled_publish", user: nil)
          published_count += 1
        end

        result = Result.new(
          processed_count: processed_count,
          published_count: published_count,
          skipped_count: skipped_count
        )
        log_result(result)
        result
      end

      private

      attr_reader :batch_size, :logger, :now, :scope

      def due_events
        scope
          .where(status: "ready_for_publish")
          .where.not(published_at: nil)
          .where("published_at <= ?", now)
      end

      def log_result(result)
        logger.info(
          "[Events::Publication::PublishScheduledEvents] " \
          "processed=#{result.processed_count} published=#{result.published_count} skipped=#{result.skipped_count}"
        )
      end

      def persist_completeness!(event)
        event.update_columns(
          completeness_score: event.completeness_score,
          completeness_flags: event.completeness_flags,
          updated_at: Time.current
        )
      end

      def normalize_now(value)
        value.respond_to?(:in_time_zone) ? value.in_time_zone : Time.zone.parse(value.to_s)
      rescue ArgumentError
        Time.current
      end
    end
  end
end
