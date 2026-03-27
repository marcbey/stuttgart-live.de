module Backend
  module Events
    class InboxState
      SESSION_FILTERS_KEY = "backend_events_inbox_filters".freeze
      SESSION_STATUS_KEY = "backend_events_inbox_status".freeze
      SESSION_NEXT_EVENT_KEY = "backend_events_next_event_enabled".freeze
      MERGE_CHANGE_TYPES = %w[all created updated].freeze
      DEFAULT_STATUS = "published".freeze

      attr_reader :status_filters

      def initialize(params:, session:, status_filters:, available_merge_run_ids: [], latest_successful_merge_run_id: nil)
        @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        @session = session
        @status_filters = status_filters
        @available_merge_run_ids = Array(available_merge_run_ids).filter_map { |value| Integer(value, exception: false) }.uniq
        @latest_successful_merge_run_id = Integer(latest_successful_merge_run_id, exception: false)
      end

      def current_status
        value = params["status"].to_s
        if valid_status?(value)
          session[SESSION_STATUS_KEY] = value
          return value
        end

        stored = session[SESSION_STATUS_KEY].to_s
        return stored if valid_status?(stored)

        DEFAULT_STATUS
      end

      def filters
        filters_for(status: current_status)
      end

      def filters_for(status:)
        session_filters.merge(status: normalized_status(status))
      end

      def navigation_status
        value = params["inbox_status"].to_s
        valid_status?(value) ? value : nil
      end

      def persist_filters!
        if clear_filters_requested?
          session.delete(SESSION_FILTERS_KEY)
        else
          merge_run_id = normalize_merge_run_id(params["merge_run_id"])
          session[SESSION_FILTERS_KEY] = {
            "query" => params["query"].to_s.strip.presence,
            "promoter_id" => params["promoter_id"].to_s.strip.presence,
            "starts_after" => params["starts_after"].to_s.strip.presence,
            "starts_before" => params["starts_before"].to_s.strip.presence,
            "merge_run_id" => merge_run_id,
            "merge_change_type" => merge_run_id == "all" ? "all" : normalize_merge_change_type(params["merge_change_type"])
          }
        end

        reset_memoized_state!
      end

      def next_event_enabled
        return @next_event_enabled if defined?(@next_event_enabled)

        value = session[SESSION_NEXT_EVENT_KEY]
        @next_event_enabled =
          if value.nil?
            false
          else
            boolean(value)
          end
      end

      def persist_next_event_preference!(value)
        normalized = boolean(value)
        session[SESSION_NEXT_EVENT_KEY] = normalized
        @next_event_enabled = normalized
      end

      private

      attr_reader :available_merge_run_ids, :latest_successful_merge_run_id, :params, :session

      def clear_filters_requested?
        boolean(params["clear_filters"])
      end

      def session_filters
        return @session_filters if defined?(@session_filters)

        stored = session[SESSION_FILTERS_KEY]
        normalized = stored.is_a?(Hash) ? stored.stringify_keys : {}
        merge_run_id = normalize_merge_run_id(normalized["merge_run_id"], legacy_merge_scope: normalized["merge_scope"])
        starts_after_value =
          if normalized.key?("starts_after")
            normalized["starts_after"].to_s.strip.presence
          else
            Date.current.iso8601
          end

        @session_filters = {
          query: normalized["query"].to_s.strip.presence,
          promoter_id: normalized["promoter_id"].to_s.strip.presence,
          starts_after: starts_after_value,
          starts_before: normalized["starts_before"].to_s.strip.presence,
          merge_run_id: merge_run_id,
          merge_change_type: merge_run_id == "all" ? "all" : normalize_merge_change_type(normalized["merge_change_type"])
        }
      end

      def normalized_status(status)
        valid_status?(status) ? status.to_s : current_status
      end

      def valid_status?(status)
        status_filters.include?(status.to_s)
      end

      def normalize_merge_run_id(value, legacy_merge_scope: nil)
        normalized = value.to_s.strip
        if normalized.blank?
          return latest_successful_merge_run_id.to_s if legacy_merge_scope.to_s.strip == "last_merge" && latest_successful_merge_run_id.present?

          return "all"
        end
        return "all" if normalized == "all"

        merge_run_id = Integer(normalized, exception: false)
        return merge_run_id.to_s if merge_run_id.present? && available_merge_run_ids.include?(merge_run_id)

        "all"
      end

      def normalize_merge_change_type(value)
        normalized = value.to_s.strip
        MERGE_CHANGE_TYPES.include?(normalized) ? normalized : "all"
      end

      def boolean(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end

      def reset_memoized_state!
        remove_instance_variable(:@session_filters) if defined?(@session_filters)
      end
    end
  end
end
