module Public
  module Events
    class SeriesCountsByIdQuery
      def self.call(scope)
        new(scope).call
      end

      def initialize(scope)
        @scope = scope
      end

      def call
        return {} if series_ids.empty?

        Event.published_live
          .except(:order)
          .where(event_series_id: series_ids)
          .where("start_at >= ?", Time.zone.today.beginning_of_day)
          .group(:event_series_id)
          .distinct
          .count(:id)
      end

      private

      attr_reader :scope

      def series_ids
        @series_ids ||=
          if scope.is_a?(ActiveRecord::Relation)
            scope
              .except(:includes, :preload, :eager_load, :order, :limit, :offset)
              .where.not(event_series_id: nil)
              .distinct
              .pluck(:event_series_id)
          else
            Array(scope).filter_map(&:event_series_id).uniq
          end
      end
    end
  end
end
