module Public
  module Events
    class SeriesRepresentativeSelector
      def self.call(events)
        new(events).call
      end

      def initialize(events)
        @events = Array(events)
      end

      def call
        representatives = representative_ids_by_series_key

        events.select do |event|
          representatives.fetch(series_key_for(event)) == event.id
        end
      end

      private

      attr_reader :events

      def representative_ids_by_series_key
        events.group_by { |event| series_key_for(event) }.transform_values do |group|
          group.min_by { |event| [ event.start_at || Time.zone.at(0), event.id.to_i ] }.id
        end
      end

      def series_key_for(event)
        event.event_series_id.presence || "event-#{event.id}"
      end
    end
  end
end
