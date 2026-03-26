module Public
  module Events
    class BrowseState
      FILTER_ALL = Public::VisibleEventsQuery::FILTER_ALL
      FILTER_SKS = Public::VisibleEventsQuery::FILTER_SKS
      FILTER_VALUES = [ FILTER_ALL, FILTER_SKS ].freeze

      attr_reader :event_date, :page, :query

      def initialize(params)
        @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        @filter = normalized_filter
        @event_date = normalized_event_date
        @query = @params["q"].to_s.strip.presence
        @normalized_query = Public::Events::SearchQueryNormalizer.normalize(@query).presence
        @page = [ @params["page"].to_i, 1 ].max
      end

      def filter
        @filter
      end

      def normalized_query
        @normalized_query
      end

      def search_query_present?
        normalized_query.present?
      end

      def event_date_param
        event_date&.iso8601
      end

      def route_params(page: nil, format: nil)
        {
          event_date: event_date_param,
          q: search_query_present? ? query : nil,
          page: page,
          format: format
        }.compact
      end

      private

      attr_reader :params

      def normalized_filter
        value = params["filter"].to_s
        FILTER_VALUES.include?(value) ? value : FILTER_SKS
      end

      def normalized_event_date
        value = params["event_date"].to_s.strip
        return if value.blank?

        Date.iso8601(value)
      rescue ArgumentError
        nil
      end
    end
  end
end
