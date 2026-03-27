module Events
  module Retention
    class PruneStaleUnpublishedEvents
      Result = Data.define(:deleted_count, :deleted_by_status, :cutoff_at)

      BATCH_SIZE = 100
      RETAINED_PUBLISHED_STATUS = "published"

      def self.call(...)
        new(...).call
      end

      def initialize(scope: Event.all, batch_size: BATCH_SIZE, logger: Rails.logger, now: Time.current)
        @scope = scope
        @batch_size = batch_size
        @logger = logger
        @cutoff_at = normalize_now(now).advance(months: -1).beginning_of_day
      end

      def call
        deleted_by_status = Hash.new(0)
        deleted_count = 0

        stale_events.find_each(batch_size: batch_size) do |event|
          deleted_by_status[event.status] += 1
          event.destroy!
          deleted_count += 1
        end

        result = Result.new(
          deleted_count: deleted_count,
          deleted_by_status: deleted_by_status.sort.to_h,
          cutoff_at: cutoff_at
        )
        log_result(result)
        result
      end

      private

      attr_reader :batch_size, :cutoff_at, :logger, :scope

      def stale_events
        scope
          .where(status: stale_statuses)
          .where("start_at < ?", cutoff_at)
      end

      def stale_statuses
        Event::STATUSES - [ RETAINED_PUBLISHED_STATUS ]
      end

      def normalize_now(value)
        value.respond_to?(:in_time_zone) ? value.in_time_zone : Time.zone.parse(value.to_s)
      rescue ArgumentError
        Time.current
      end

      def log_result(result)
        logger.info(
          "[Events::Retention::PruneStaleUnpublishedEvents] " \
          "deleted=#{result.deleted_count} cutoff_at=#{result.cutoff_at.iso8601} " \
          "deleted_by_status=#{result.deleted_by_status}"
        )
      end
    end
  end
end
