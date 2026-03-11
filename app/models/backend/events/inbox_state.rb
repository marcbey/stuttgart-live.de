module Backend
  module Events
    class InboxState
      SESSION_FILTERS_KEY = "backend_events_inbox_filters".freeze
      SESSION_STATUS_KEY = "backend_events_inbox_status".freeze
      SESSION_NEXT_EVENT_KEY = "backend_events_next_event_enabled".freeze
      MERGE_SCOPES = %w[all last_merge].freeze
      MERGE_CHANGE_TYPES = %w[all created updated].freeze
      DEFAULT_STATUS = "published".freeze

      attr_reader :status_filters

      def initialize(params:, session:, status_filters:)
        @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
        @session = session
        @status_filters = status_filters
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
          session[SESSION_FILTERS_KEY] = {
            "query" => params["query"].to_s.strip.presence,
            "promoter_id" => params["promoter_id"].to_s.strip.presence,
            "starts_after" => params["starts_after"].to_s.strip.presence,
            "starts_before" => params["starts_before"].to_s.strip.presence,
            "merge_scope" => normalize_merge_scope(params["merge_scope"]),
            "merge_change_type" => normalize_merge_change_type(params["merge_change_type"])
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

      attr_reader :params, :session

      def clear_filters_requested?
        boolean(params["clear_filters"])
      end

      def session_filters
        return @session_filters if defined?(@session_filters)

        stored = session[SESSION_FILTERS_KEY]
        normalized = stored.is_a?(Hash) ? stored.stringify_keys : {}
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
          merge_scope: normalize_merge_scope(normalized["merge_scope"]),
          merge_change_type: normalize_merge_change_type(normalized["merge_change_type"])
        }
      end

      def normalized_status(status)
        valid_status?(status) ? status.to_s : current_status
      end

      def valid_status?(status)
        status_filters.include?(status.to_s)
      end

      def normalize_merge_scope(value)
        normalized = value.to_s.strip
        MERGE_SCOPES.include?(normalized) ? normalized : "all"
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
