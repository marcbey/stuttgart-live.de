module Editorial
  class EventsInboxQuery
    DEFAULT_LIMIT = 120
    MERGE_CHANGE_TYPES = %w[all created updated].freeze

    def initialize(scope: Event.all, params: {})
      @scope = scope
      @params = params
    end

    def call
      relation = scope.with_attached_promotion_banner_image.includes(
        :llm_enrichment,
        :genres,
        :event_offers,
        :import_event_images,
        :event_change_logs,
        event_images: [ file_attachment: :blob ]
      )
      relation = relation.where(status: status_filter) if status_filter.present?
      relation = relation.where("start_at >= ?", starts_after.beginning_of_day) if starts_after.present?
      relation = relation.where("start_at <= ?", starts_before.end_of_day) if starts_before.present?
      relation = apply_merge_change_filter(relation)
      if promoter_id.present?
        token = "%#{promoter_id.downcase}%"
        relation = relation.where("LOWER(COALESCE(promoter_id, '')) LIKE :q", q: token)
      end

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

    def promoter_id
      params[:promoter_id].to_s.strip.presence
    end

    def apply_merge_change_filter(relation)
      return relation if merge_run_filter_disabled?
      return relation.none if merge_run_id.blank?

      relation.where(
        id: EventChangeLog.where(
          action: merge_actions,
          event_id: relation.select(:id)
        ).where("metadata ->> 'merge_run_id' = ?", merge_run_id.to_s).select(:event_id)
      )
    end

    def merge_run_filter_disabled?
      raw_value = params[:merge_run_id].to_s.strip
      raw_value.blank? || raw_value == "all"
    end

    def merge_change_type
      raw_value = params[:merge_change_type].to_s.strip
      return raw_value if MERGE_CHANGE_TYPES.include?(raw_value)

      "all"
    end

    def merge_actions
      case merge_change_type
      when "created"
        [ "merged_create" ]
      when "updated"
        [ "merged_update" ]
      else
        [ "merged_create", "merged_update" ]
      end
    end

    def merge_run_id
      Integer(params[:merge_run_id], exception: false)
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
