module Merging
  class MatchConfig
    SIMILARITY_MATCH_THRESHOLD = 0.74
    START_AT_MATCH_TOLERANCE = 1.hour

    class << self
      def similarity_matching_enabled?
        AppSetting.merge_artist_similarity_matching_enabled?
      end

      def similarity_match_threshold
        SIMILARITY_MATCH_THRESHOLD
      end

      def start_at_match_tolerance
        START_AT_MATCH_TOLERANCE
      end
    end
  end
end
