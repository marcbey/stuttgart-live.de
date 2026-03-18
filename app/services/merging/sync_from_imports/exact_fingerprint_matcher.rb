module Merging
  class SyncFromImports
    class ExactFingerprintMatcher
      def initialize(priority_map:)
        @priority_map = priority_map
      end

      def call(record:)
        Event
          .where(start_at: record.start_at, normalized_artist_name: normalized_artist_name_for(record))
          .to_a
          .min_by { |event| [ priority_for(event.primary_source), event.id.to_i ] }
      end

      private

      attr_reader :priority_map

      def normalized_artist_name_for(record)
        Merging::ArtistNameNormalizer.normalize(record.artist_name)
      end

      def priority_for(source)
        priority_map.fetch(source, 999)
      end
    end
  end
end
