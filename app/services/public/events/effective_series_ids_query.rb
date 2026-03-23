module Public
  module Events
    class EffectiveSeriesIdsQuery
      def self.call(scope)
        new(scope).call
      end

      def initialize(scope)
        @scope = scope
      end

      def call
        return [] if series_ids.empty?

        Event.published_live
          .except(:order)
          .where(event_series_id: series_ids)
          .group(:event_series_id)
          .having("COUNT(DISTINCT events.id) >= 2")
          .pluck(:event_series_id)
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
