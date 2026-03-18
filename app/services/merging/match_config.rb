module Merging
  class MatchConfig
    SIMILARITY_MATCH_THRESHOLD = 0.74

    class << self
      def similarity_matching_enabled?
        AppSetting.merge_artist_similarity_matching_enabled?
      end

      def similarity_match_threshold
        SIMILARITY_MATCH_THRESHOLD
      end
    end
  end
end
