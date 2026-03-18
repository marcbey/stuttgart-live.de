module Merging
  class SyncFromImports
    class ArtistSimilarityMatcher
      Result = Data.define(:event, :score, :reason)

      def initialize(priority_map:, threshold: Merging::MatchConfig.similarity_match_threshold)
        @priority_map = priority_map
        @threshold = threshold
      end

      def call(record:)
        candidates = Event.where(start_at: record.start_at).to_a
        best_result = candidates.filter_map { |event| match_result_for(record:, event:) }.max_by { |result| result.score }
        return nil if best_result.nil? || best_result.score < threshold

        best_result
      end

      private

      attr_reader :priority_map, :threshold

      def match_result_for(record:, event:)
        score, reason = score(record.artist_name, event.artist_name)
        return nil if score <= 0

        Result.new(event:, score:, reason:)
      end

      def score(left_name, right_name)
        left_normalized = Merging::ArtistNameNormalizer.normalize(left_name)
        right_normalized = event_normalized_name(right_name)

        return [ 1.0, "normalized_artist_name_exact" ] if left_normalized == right_normalized

        left_tokens = Merging::ArtistNameNormalizer.significant_tokens(left_name)
        right_tokens = Merging::ArtistNameNormalizer.significant_tokens(right_name)
        return [ 0.0, nil ] if left_tokens.empty? || right_tokens.empty?

        left_unique = left_tokens.uniq
        right_unique = right_tokens.uniq

        return [ 0.95, "significant_tokens_exact" ] if left_unique == right_unique

        intersection = (left_unique & right_unique).size
        union = (left_unique | right_unique).size
        return [ 0.0, nil ] if intersection.zero? || union.zero?

        left_contained = (left_unique - right_unique).empty?
        right_contained = (right_unique - left_unique).empty?
        if left_contained || right_contained
          return [ 0.84, "significant_tokens_subset" ]
        end

        jaccard = intersection.to_f / union
        [ jaccard, "significant_tokens_overlap" ]
      end

      def event_normalized_name(value)
        Merging::ArtistNameNormalizer.normalize(value)
      end
    end
  end
end
