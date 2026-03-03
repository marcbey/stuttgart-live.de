module Editorial
  class EventsInboxQuery
    DEFAULT_LIMIT = 120

    def initialize(scope: Event.all, params: {})
      @scope = scope
      @params = params
    end

    def call
      relation = scope.includes(:genres, :event_offers)
      relation = relation.where(status: status_filter) if status_filter.present?
      relation = relation.where("start_at >= ?", starts_after.beginning_of_day) if starts_after.present?
      relation = relation.where("start_at <= ?", starts_before.end_of_day) if starts_before.present?

      if query.present?
        token = "%#{query.downcase}%"
        relation = relation.where(
          "LOWER(title) LIKE :q OR LOWER(artist_name) LIKE :q OR LOWER(city) LIKE :q OR LOWER(venue) LIKE :q",
          q: token
        )
      end

      relation.chronological.limit(limit)
    end

    private

    attr_reader :scope, :params

    def status_filter
      value = params[:status].to_s
      value if Event::STATUSES.include?(value)
    end

    def starts_after
      parse_date(params[:starts_after])
    end

    def starts_before
      parse_date(params[:starts_before])
    end

    def query
      params[:query].to_s.strip.presence
    end

    def limit
      parsed = params[:limit].to_i
      return DEFAULT_LIMIT if parsed <= 0

      [ parsed, 500 ].min
    end

    def parse_date(raw)
      return nil if raw.blank?

      Date.parse(raw.to_s)
    rescue ArgumentError
      nil
    end
  end
end
