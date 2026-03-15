module Public
  class VisibleEventsQuery
    FILTER_ALL = "all".freeze
    FILTER_SKS = "sks".freeze

    def initialize(scope: Event.published_live, filter: FILTER_ALL, event_date: nil, query: nil)
      @scope = scope
      @filter = filter
      @event_date = event_date
      @query = query.to_s.strip.presence
    end

    def call
      relation = scope
      relation = relation.where(start_at: event_date.beginning_of_day..event_date.end_of_day) if event_date.present?
      relation = apply_query(relation) if query.present?
      return relation unless filter == FILTER_SKS

      relation.where(promoter_id: Event.sks_promoter_ids)
    end

    private

    attr_reader :scope, :filter, :event_date, :query

    def apply_query(relation)
      token = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"

      relation.where(
        "events.artist_name ILIKE :token OR events.title ILIKE :token OR events.venue ILIKE :token OR events.city ILIKE :token",
        token: token
      )
    end
  end
end
