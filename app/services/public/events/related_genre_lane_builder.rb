module Public
  module Events
    class RelatedGenreLaneBuilder
      Lane = Data.define(:group, :events, :effective_series_ids)

      DEFAULT_LIMIT = 20

      def initialize(event:, relation:, limit: DEFAULT_LIMIT)
        @event = event
        @relation = relation
        @limit = limit
      end

      def call
        return if group.blank?

        events, effective_series_ids = chronological_group_events
        return if events.empty?

        Lane.new(group:, events:, effective_series_ids:)
      end

      private

      attr_reader :event, :limit, :relation

      def group
        @group ||= event.primary_genre
      end

      def chronological_group_events
        selected_events = ranked_events
        events = series_representatives(selected_events).first(limit)
        effective_series_ids = effective_series_ids_for(events)

        [ events, effective_series_ids ]
      end

      def ranked_events
        candidate_events
          .filter_map { |candidate| ranked_candidate(candidate) }
          .sort_by { |ranked_candidate| ranked_candidate.fetch(:sort_key) }
          .map { |ranked_candidate| ranked_candidate.fetch(:event) }
      end

      def candidate_events
        relation
          .left_outer_joins(:genres, :sub_genres)
          .where(candidate_match_predicate, candidate_match_values)
          .where.not(id: event.id)
          .then { |scope| exclude_current_series(scope) }
          .distinct
          .preload(:genres, :sub_genres)
          .to_a
      end

      def candidate_match_predicate
        predicates = []
        predicates << "genres.id IN (:genre_ids)" if genre_ids.any?
        predicates << "sub_genres.id IN (:sub_genre_ids)" if sub_genre_ids.any?
        predicates.join(" OR ")
      end

      def candidate_match_values
        {
          genre_ids: genre_ids,
          sub_genre_ids: sub_genre_ids
        }
      end

      def exclude_current_series(scope)
        return scope if event.event_series_id.blank?

        scope.where(
          "events.event_series_id IS NULL OR events.event_series_id != ?",
          event.event_series_id
        )
      end

      def ranked_candidate(candidate)
        candidate_genre_ids = sorted_association_ids(candidate, :genres)
        candidate_sub_genre_ids = sorted_association_ids(candidate, :sub_genres)
        sub_genre_overlap_count = (candidate_sub_genre_ids & sub_genre_ids).size
        genre_overlap_count = (candidate_genre_ids & genre_ids).size
        rank = candidate_rank(
          candidate_genre_ids: candidate_genre_ids,
          candidate_sub_genre_ids: candidate_sub_genre_ids,
          sub_genre_overlap_count: sub_genre_overlap_count,
          genre_overlap_count: genre_overlap_count
        )
        return if rank.blank?

        {
          event: candidate,
          sort_key: sort_key_for(
            candidate,
            rank: rank,
            sub_genre_overlap_count: sub_genre_overlap_count
          )
        }
      end

      def candidate_rank(candidate_genre_ids:, candidate_sub_genre_ids:, sub_genre_overlap_count:, genre_overlap_count:)
        return 0 if exact_sub_genre_match?(candidate_sub_genre_ids)
        return 1 if sub_genre_overlap_count.positive?
        return 2 if exact_two_genre_match?(candidate_genre_ids)

        3 if genre_overlap_count.positive?
      end

      def exact_sub_genre_match?(candidate_sub_genre_ids)
        sub_genre_ids.any? && candidate_sub_genre_ids == sub_genre_ids
      end

      def exact_two_genre_match?(candidate_genre_ids)
        genre_ids.size == 2 && candidate_genre_ids == genre_ids
      end

      def sort_key_for(candidate, rank:, sub_genre_overlap_count:)
        [
          rank,
          sub_genre_overlap_sort_value(rank, sub_genre_overlap_count),
          priority_sort_value(candidate),
          candidate.start_at || Time.zone.at(0),
          candidate.id.to_i
        ]
      end

      def sub_genre_overlap_sort_value(rank, sub_genre_overlap_count)
        rank == 1 ? -sub_genre_overlap_count : 0
      end

      def priority_sort_value(candidate)
        candidate.promoter_id.in?(Event.sks_promoter_ids) || candidate.highlighted? ? 0 : 1
      end

      def series_representatives(events)
        seen_series_keys = {}

        events.select do |candidate|
          series_key = series_key_for(candidate)
          next false if seen_series_keys.key?(series_key)

          seen_series_keys[series_key] = true
          true
        end
      end

      def series_key_for(candidate)
        candidate.event_series_id.presence || "event-#{candidate.id}"
      end

      def effective_series_ids_for(events)
        EffectiveSeriesIdsQuery.call(events)
      end

      def genre_ids
        @genre_ids ||= sorted_association_ids(event, :genres)
      end

      def sub_genre_ids
        @sub_genre_ids ||= sorted_association_ids(event, :sub_genres)
      end

      def sorted_association_ids(record, association_name)
        if record.association(association_name).loaded?
          return record.public_send(association_name).map(&:id).sort
        end

        record.public_send(association_name).order(:id).pluck(:id)
      end
    end
  end
end
