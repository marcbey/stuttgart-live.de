module Public
  class VisibleEventsQuery
    FILTER_ALL = "all".freeze
    FILTER_SKS = "sks".freeze

    def initialize(scope: Event.published_live, filter: FILTER_ALL, event_date: nil, query: nil)
      @scope = scope
      @filter = filter
      @event_date = event_date
      @raw_query = query.to_s.strip.presence
      @normalized_query = Public::Events::SearchQueryNormalizer.normalize(query).presence
    end

    def call
      relation = scope
      relation = relation.where(start_at: event_date.beginning_of_day..event_date.end_of_day) if event_date.present?
      relation = apply_query(relation) if normalized_query.present?
      relation = relation.homepage_highlights if filter == FILTER_SKS
      relation = relation.search_priority_first if normalized_query.present?

      relation
    end

    private

    attr_reader :scope, :filter, :event_date, :raw_query, :normalized_query

    def apply_query(relation)
      patterns = Public::Events::SearchQueryNormalizer.wildcard_patterns(raw_query)
      return relation if patterns.empty?

      binds = {}
      conditions = patterns.each_with_index.map do |pattern, index|
        binds[:"pattern_#{index}"] = pattern
        "#{searchable_text_sql} ILIKE :pattern_#{index}"
      end

      raw_token = "%#{ActiveRecord::Base.sanitize_sql_like(raw_query)}%"
      binds[:raw_token] = raw_token

      relation.where(
        [
          *conditions,
          "events.artist_name ILIKE :raw_token",
          "events.title ILIKE :raw_token",
          "events.venue ILIKE :raw_token",
          "events.city ILIKE :raw_token"
        ].join(" OR "),
        binds
      )
    end

    def searchable_text_sql
      <<~SQL.squish
        COALESCE(events.artist_name, '') || ' ' ||
        COALESCE(events.title, '') || ' ' ||
        COALESCE(events.venue, '') || ' ' ||
        COALESCE(events.city, '')
      SQL
    end
  end
end
