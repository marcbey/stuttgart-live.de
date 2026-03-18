module Merging
  class SyncFromImports
    class MatchStrategy
      Result = Data.define(:event, :reason, :score)

      def initialize(priority_map:, config: Merging::MatchConfig)
        @config = config
        @exact_matcher = ExactFingerprintMatcher.new(priority_map:)
        @similarity_matcher = ArtistSimilarityMatcher.new(priority_map:)
      end

      def call(records:)
        source_snapshot_match(records) ||
          exact_match(records.first) ||
          similarity_match(records.first)
      end

      private

      attr_reader :config, :exact_matcher, :similarity_matcher

      def source_snapshot_match(records)
        records.each do |record|
          event =
            Event.where(
              "source_snapshot -> 'sources' @> ?",
              [ { "source" => record.source, "external_event_id" => record.external_event_id } ].to_json
            ).first
          return Result.new(event:, reason: "source_snapshot", score: 1.0) if event.present?
        end

        nil
      end

      def exact_match(record)
        event = exact_matcher.call(record:)
        return nil if event.nil?

        Result.new(event:, reason: "exact_fingerprint", score: 1.0)
      end

      def similarity_match(record)
        return nil unless config.similarity_matching_enabled?

        result = similarity_matcher.call(record:)
        return nil if result.nil?

        Result.new(event: result.event, reason: result.reason, score: result.score)
      end
    end
  end
end
