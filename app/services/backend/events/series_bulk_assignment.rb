module Backend
  module Events
    class SeriesBulkAssignment
      def initialize(events:, user:)
        @events = events
        @user = user
      end

      def assign!
        series = EventSeries.create!(origin: "manual", name: derived_series_name)
        previous_series_ids = []

        events.find_each do |event|
          previous_series_ids << event.event_series_id if event.event_series_id.present?
          event.update!(event_series: series, event_series_assignment: "manual")
          Editorial::EventChangeLogger.log!(
            event: event,
            action: "bulk_group_as_series",
            user: user,
            metadata: series_change_metadata(series)
          )
        end

        cleanup_series_ids!(previous_series_ids, except_id: series.id)
        events.count
      end

      def remove!
        previous_series_ids = []

        events.find_each do |event|
          previous_series_ids << event.event_series_id if event.event_series_id.present?
          event.update!(event_series: nil, event_series_assignment: "manual_none")
          Editorial::EventChangeLogger.log!(
            event: event,
            action: "bulk_remove_from_series",
            user: user
          )
        end

        cleanup_series_ids!(previous_series_ids)
        events.count
      end

      private

      attr_reader :events, :user

      def derived_series_name
        selected_events = events.reorder(:start_at, :id).to_a
        titles = selected_events.map { |event| event.title.to_s.strip }.reject(&:blank?).uniq
        return titles.first if titles.one?

        titles.first.presence ||
          selected_events.first&.artist_name.to_s.strip.presence ||
          "Event-Reihe"
      end

      def cleanup_series_ids!(series_ids, except_id: nil)
        series_ids.compact.uniq.each do |series_id|
          next if except_id.present? && series_id == except_id

          EventSeries.find_by(id: series_id)&.destroy_if_orphaned!
        end
      end

      def series_change_metadata(series)
        {
          "event_series_id" => series.id,
          "event_series_origin" => series.origin,
          "event_series_name" => series.name
        }
      end
    end
  end
end
