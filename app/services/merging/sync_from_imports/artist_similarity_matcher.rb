module Merging
  class SyncFromImports
    class ArtistSimilarityMatcher
      Result = Data.define(:event, :score, :reason)

      def initialize(
        priority_map:,
        threshold: Merging::MatchConfig.similarity_match_threshold,
        start_at_tolerance: Merging::MatchConfig.start_at_match_tolerance
      )
        @priority_map = priority_map
        @threshold = threshold
        @start_at_tolerance = start_at_tolerance
      end

      def call(record:)
        candidates = Event.where(start_at: start_at_range_for(record)).to_a
        best_result = candidates
          .filter_map { |event| match_result_for(record:, event:) }
          .max_by { |result| [ result.score, -start_at_distance_seconds(record:, event: result.event), -priority_for(result.event.primary_source) ] }
        return nil if best_result.nil? || best_result.score < threshold

        best_result
      end

      private

      attr_reader :priority_map, :start_at_tolerance, :threshold

      def match_result_for(record:, event:)
        [
          artist_match_result_for(record:, event:),
          artist_title_swap_match_result_for(record:, event:),
          title_subset_match_result_for(record:, event:)
        ].compact.max_by(&:score)
      end

      def artist_match_result_for(record:, event:)
        score, reason = score(record.artist_name, event.artist_name)
        return nil if score <= 0

        Result.new(event:, score:, reason:)
      end

      def artist_title_swap_match_result_for(record:, event:)
        return nil unless distinct_artist_title_pair?(artist_name: record.artist_name, title: record.title)
        return nil unless distinct_artist_title_pair?(artist_name: event.artist_name, title: event.title)

        artist_to_title_score, = score(record.artist_name, event.title)
        title_to_artist_score, = score(record.title, event.artist_name)
        return nil if artist_to_title_score < threshold || title_to_artist_score < threshold

        Result.new(event:, score: [ artist_to_title_score, title_to_artist_score ].min, reason: "artist_title_swap")
      end

      def title_subset_match_result_for(record:, event:)
        return nil unless matching_venue?(record:, event:)
        return nil unless distinctive_title?(record.title) && distinctive_title?(event.title)

        title_score, reason = score(record.title, event.title)
        return nil if title_score < threshold
        return nil unless title_subset_reason?(reason)

        Result.new(event:, score: title_score, reason: "title_#{reason}_same_venue")
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

      def distinct_artist_title_pair?(artist_name:, title:)
        normalized_artist_name = Merging::ArtistNameNormalizer.normalize(artist_name)
        normalized_title = Merging::ArtistNameNormalizer.normalize(title)

        normalized_artist_name.present? &&
          normalized_title.present? &&
          normalized_artist_name != normalized_title
      end

      def matching_venue?(record:, event:)
        record_key = Venue.canonical_match_key(record.venue)
        event_key = Venue.canonical_match_key(event.venue)

        record_key.present? && record_key == event_key
      end

      def distinctive_title?(value)
        tokens = Merging::ArtistNameNormalizer.significant_tokens(value).uniq
        return false if tokens.empty?

        tokens.sum(&:length) >= 8 && tokens.any? { |token| token.length >= 5 }
      end

      def title_subset_reason?(reason)
        %w[
          normalized_artist_name_exact
          significant_tokens_exact
          significant_tokens_subset
        ].include?(reason)
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
