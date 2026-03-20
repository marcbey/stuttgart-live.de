module LlmGenreGrouping
  class Lookup
    class << self
      def active_snapshot
        LlmGenreGroupingSnapshot.active.includes(:groups).first
      end

      def groups_for_event(event)
        genres = normalized_event_genres(event)
        return LlmGenreGroupingGroup.none if genres.empty?

        snapshot = active_snapshot
        return LlmGenreGroupingGroup.none if snapshot.blank?

        matching_groups(snapshot.groups, genres)
      end

      def events_for_group(group, relation: Event.all)
        genres = normalize_genres(group.member_genres)
        return relation.none if genres.empty?

        relation
          .joins(:llm_enrichment)
          .where(
            "EXISTS (" \
              "SELECT 1 FROM jsonb_array_elements_text(event_llm_enrichments.genre) AS event_genre(value) " \
              "WHERE event_genre.value IN (?)" \
            ")",
            genres
          )
          .distinct
      end

      private

      def normalized_event_genres(event)
        enrichment = event.respond_to?(:llm_enrichment) ? event.llm_enrichment : nil
        normalize_genres(enrichment&.genre)
      end

      def normalize_genres(genres)
        Array(genres).filter_map do |entry|
          value = entry.to_s.strip
          value.presence
        end.uniq.sort
      end

      def matching_groups(groups_relation, genres)
        groups_relation.where(
          "EXISTS (" \
            "SELECT 1 FROM jsonb_array_elements_text(member_genres) AS member_genre(value) " \
            "WHERE member_genre.value IN (?)" \
          ")",
          genres
        )
      end
    end
  end
end
