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

      raw_token = "%#{ActiveRecord::Base.sanitize_sql_like(raw_query)}%"
      searchable_text = searchable_text_node
      columns = searchable_columns

      wildcard_matches = patterns.map { |pattern| searchable_text.matches(pattern) }
      raw_matches = columns.map { |column| column.matches(raw_token) }
      predicate = (wildcard_matches + raw_matches).reduce { |combined, condition| combined.or(condition) }

      relation.where(predicate)
    end

    def searchable_columns
      events = Event.arel_table
      [ events[:artist_name], events[:title], events[:venue], events[:city] ]
    end

    def searchable_text_node
      searchable_columns.map do |column|
        Arel::Nodes::NamedFunction.new("COALESCE", [ column, Arel::Nodes.build_quoted("") ])
      end.reduce do |combined, column|
        combined
          .concat(Arel::Nodes.build_quoted(" "))
          .concat(column)
      end
    end
  end
end
