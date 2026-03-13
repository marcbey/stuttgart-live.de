module Public
  module Events
    class BrowseState
      FILTER_ALL = Public::VisibleEventsQuery::FILTER_ALL
      FILTER_SKS = Public::VisibleEventsQuery::FILTER_SKS
      FILTER_VALUES = [ FILTER_ALL, FILTER_SKS ].freeze

      VIEW_GRID = "grid".freeze
      VIEW_LIST = "list".freeze
      VIEW_VALUES = [ VIEW_GRID, VIEW_LIST ].freeze

      attr_reader :event_date, :page, :query, :view

      def initialize(params)
        @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        @view = normalized_view
        @filter = normalized_filter
        @event_date = normalized_event_date
        @query = @params["q"].to_s.strip.presence
        @page = [ @params["page"].to_i, 1 ].max
      end

      def filter
        @filter
      end

      def event_date_param
        event_date&.iso8601
      end

      def grid?
        view == VIEW_GRID
      end

      def list?
        view == VIEW_LIST
      end

      def route_params(page: nil, view: self.view, format: nil)
        {
          view: view_param_for(view),
          event_date: event_date_param,
          q: query,
          page: page,
          format: format
        }.compact
      end

      private

      attr_reader :params

      def normalized_filter
        return FILTER_ALL if list?

        value = params["filter"].to_s
        FILTER_VALUES.include?(value) ? value : FILTER_SKS
      end

      def normalized_view
        value = params["view"].to_s
        VIEW_VALUES.include?(value) ? value : VIEW_GRID
      end

      def normalized_event_date
        value = params["event_date"].to_s.strip
        return if value.blank?

        Date.iso8601(value)
      rescue ArgumentError
        nil
      end

      def view_param_for(view)
        view.to_s == VIEW_LIST ? VIEW_LIST : nil
      end
    end
  end
end
