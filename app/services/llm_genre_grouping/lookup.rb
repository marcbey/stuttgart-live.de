module LlmGenreGrouping
  class Lookup
    DEFAULT_GROUP_EVENTS_LIMIT = 100

    class << self
      def selected_snapshot
        snapshot_id = AppSetting.public_genre_grouping_snapshot_id
        return if snapshot_id.blank?

        LlmGenreGroupingSnapshot.includes(:groups, :homepage_genre_lane_configuration).find_by(id: snapshot_id)
      end

      def groups_for_event(event)
        genres = normalized_event_genres(event)
        return LlmGenreGroupingGroup.none if genres.empty?

        snapshot = selected_snapshot
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

      def prioritized_events_for_group(group, relation: Event.all, limit: DEFAULT_GROUP_EVENTS_LIMIT, exclude_event_id: nil)
        scoped_relation = events_for_group(group, relation:)
        scoped_relation = scoped_relation.where.not(id: exclude_event_id) if exclude_event_id.present?

        ordered_relation = scoped_relation
          .select("events.*, #{group_event_priority_order_sql} AS genre_group_event_priority")
          .reorder(Arel.sql("genre_group_event_priority ASC"), :start_at, :id)

        return ordered_relation if limit.nil?

        ordered_relation.limit(limit)
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

      def group_event_priority_order_sql
        quoted_ids = Event.sks_promoter_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(", ")
        sks_clause = quoted_ids.present? ? "WHEN events.promoter_id IN (#{quoted_ids}) THEN 1 " : ""

        "CASE WHEN events.highlighted = TRUE THEN 0 #{sks_clause}ELSE 2 END"
      end
    end
  end
end
