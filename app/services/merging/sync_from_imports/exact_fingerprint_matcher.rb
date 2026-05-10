module Merging
  class SyncFromImports
    class ExactFingerprintMatcher
      def initialize(priority_map:, start_at_tolerance: Merging::MatchConfig.start_at_match_tolerance)
        @priority_map = priority_map
        @start_at_tolerance = start_at_tolerance
      end

      def call(record:)
        Event
          .where(start_at: start_at_range_for(record), normalized_artist_name: normalized_artist_name_for(record))
          .to_a
          .min_by { |event| [ start_at_distance_seconds(record:, event:), priority_for(event.primary_source), event.id.to_i ] }
      end

      private

      attr_reader :priority_map, :start_at_tolerance

      def normalized_artist_name_for(record)
        Merging::ArtistNameNormalizer.normalize(record.artist_name)
      end

      def priority_for(source)
        priority_map.fetch(source, 999)
      end

      def start_at_range_for(record)
        (record.start_at - start_at_tolerance)..(record.start_at + start_at_tolerance)
      end

      def start_at_distance_seconds(record:, event:)
        (event.start_at - record.start_at).abs
      end
    end
  end
end
