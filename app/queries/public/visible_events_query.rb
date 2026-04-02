module Public
  class VisibleEventsQuery
    FILTER_ALL = "all".freeze
    FILTER_SKS = "sks".freeze

    def initialize(scope: Event.published_live, filter: FILTER_ALL, event_date: nil, query: nil, structured: true)
      @scope = scope
      @filter = filter
      @event_date = event_date
      @raw_query = query.to_s.strip.presence
      @normalized_query = Public::Events::SearchQueryNormalizer.normalize(query).presence
      @compact_query = Public::Events::SearchQueryNormalizer.compact_normalize(query).presence
      @analysis = Public::Events::Search::Analyzer.call(query)
      @structured = structured
    end

    def call
      relation = scope.left_outer_joins(:venue_record)
      relation = relation.where(start_at: event_date.beginning_of_day..event_date.end_of_day) if event_date.present?
      return relation.none if structured? && analysis.time_incomplete?

      relation = apply_structured_query(relation) if structured? && analysis.ready_for_event_search?
      relation = apply_query(relation) if (!structured? || analysis.fallback_text?) && normalized_query.present?
      relation = relation.homepage_highlights if filter == FILTER_SKS
      relation = relation.search_priority_first if search_query_present?

      relation
    end

    private

    attr_reader :scope, :filter, :event_date, :raw_query, :normalized_query, :compact_query, :analysis, :structured

    def structured?
      structured
    end

    def search_query_present?
      raw_query.present? && (analysis.ready_for_event_search? || normalized_query.present?)
    end

    def apply_structured_query(relation)
      relation = relation.where(start_at: analysis.resolution.from..analysis.resolution.to)
      return relation unless analysis.venue_query.present?

      relation.where(venue_id: Venue.strict_matching_query(analysis.venue_query).select(:id))
    end

    def apply_query(relation)
      patterns = Public::Events::SearchQueryNormalizer.wildcard_patterns(raw_query)
      return relation if patterns.empty?

      raw_token = "%#{ActiveRecord::Base.sanitize_sql_like(raw_query)}%"
      searchable_text = searchable_text_node
      compact_searchable_text = compact_searchable_text_node
      columns = searchable_columns

      wildcard_matches = patterns.map { |pattern| searchable_text.matches(pattern) }
      raw_matches = columns.map { |column| column.matches(raw_token) }
      compact_matches = compact_query.present? ? [ compact_searchable_text.matches("%#{compact_query}%") ] : []
      predicate = (wildcard_matches + raw_matches + compact_matches).reduce { |combined, condition| combined.or(condition) }

      relation.where(predicate)
    end

    def searchable_columns
      events = Event.arel_table
      venues = Venue.arel_table
      [ events[:artist_name], events[:normalized_artist_name], events[:title], venues[:name], events[:city] ]
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

    def compact_searchable_text_node
      searchable_columns.map do |column|
        compact_text_node_for(column)
      end.reduce do |combined, column|
        combined.concat(column)
      end
    end

    def compact_text_node_for(column)
      normalized_column = Arel::Nodes::NamedFunction.new("LOWER", [
        Arel::Nodes::NamedFunction.new("COALESCE", [ column, Arel::Nodes.build_quoted("") ])
      ])

      Arel::Nodes::NamedFunction.new("REGEXP_REPLACE", [
        normalized_column,
        Arel::Nodes.build_quoted("[^[:alnum:]]+"),
        Arel::Nodes.build_quoted(""),
        Arel::Nodes.build_quoted("g")
      ])
    end
  end
end
