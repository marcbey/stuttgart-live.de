module Public
  module Events
    module Search
      class VenueSuggester
        SHORT_QUERY_LENGTH = 3

        def self.call(query, limit: 6)
          new(query, limit:).call
        end

        def initialize(query, limit:)
          @query = query.to_s.strip
          @limit = limit
        end

        def call
          return Venue.none if query.blank?

          Venue.search_by_query(query, limit:)
        end

        private

        attr_reader :query, :limit
      end
    end
  end
end
