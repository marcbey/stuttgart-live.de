require "set"

module Public
  module Events
    class HomepageLanePager
      Result = Data.define(:events, :effective_series_ids, :next_cursor, :card_offset)

      DEFAULT_PER_PAGE = 10
      MAX_PER_PAGE = 20
      BATCH_MULTIPLIER = 4
      CURSOR_SALT = "public/events/homepage_lane_cursor"

      class InvalidCursor < StandardError; end

      def self.decode_cursor(cursor)
        return if cursor.blank?

        verifier.verify(cursor)
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        nil
      end

      def self.verifier
        Rails.application.message_verifier(CURSOR_SALT)
      end

      def initialize(relation:, context:, cursor: nil, per_page: DEFAULT_PER_PAGE)
        @relation = relation
        @context = normalized_context(context)
        @per_page = normalized_per_page(per_page)
        @cursor_payload = self.class.decode_cursor(cursor)
        raise InvalidCursor if cursor.present? && @cursor_payload.blank?
        raise InvalidCursor if @cursor_payload.present? && @cursor_payload.fetch("context", {}) != @context
      end

      def call
        events, next_state = paged_events

        Result.new(
          events: events,
          effective_series_ids: EffectiveSeriesIdsQuery.call(events),
          next_cursor: next_cursor_for(next_state),
          card_offset: position
        )
      end

      private

      attr_reader :context, :cursor_payload, :per_page, :relation

      def paged_events
        selected_events = []
        seen_series = seen_series_ids
        current_relation = apply_cursor(relation)
        last_scanned_event = nil

        loop do
          batch = current_relation.limit(batch_size).to_a
          break if batch.empty?

          batch.each do |event|
            last_scanned_event = event
            series_id = event.event_series_id
            next if series_id.present? && seen_series.include?(series_id.to_i)

            selected_events << event
            seen_series << series_id.to_i if series_id.present?
            break if selected_events.size >= per_page
          end

          break if selected_events.size >= per_page
          break if batch.size < batch_size

          current_relation = relation_after(last_scanned_event)
        end

        [ selected_events, state_for(last_scanned_event, seen_series, selected_events.size) ]
      end

      def next_cursor_for(state)
        return if state.blank?
        return unless state.fetch("last_start_at").present?
        return unless relation_after_state(state).exists?

        self.class.verifier.generate({
          "context" => context,
          "state" => state
        })
      end

      def state_for(event, seen_series_ids, selected_count)
        return if event.blank?

        {
          "last_start_at" => event.start_at.iso8601(6),
          "last_id" => event.id,
          "seen_series_ids" => seen_series_ids.to_a,
          "position" => position + selected_count
        }
      end

      def apply_cursor(scope)
        state = cursor_state
        return scope unless state.present?

        relation_after_state(state, scope:)
      end

      def relation_after(event)
        return relation.none if event.blank?

        relation_after_position(event.start_at, event.id)
      end

      def relation_after_state(state, scope: relation)
        start_at = Time.zone.parse(state.fetch("last_start_at"))
        id = state.fetch("last_id")

        relation_after_position(start_at, id, scope:)
      end

      def relation_after_position(start_at, id, scope: relation)
        scope.where("events.start_at > :start_at OR (events.start_at = :start_at AND events.id > :id)", start_at:, id:)
      end

      def cursor_state
        cursor_payload&.fetch("state", nil)
      end

      def seen_series_ids
        Set.new(Array(cursor_state&.fetch("seen_series_ids", [])).map(&:to_i))
      end

      def position
        cursor_state&.fetch("position", 0).to_i
      end

      def batch_size
        [ per_page * BATCH_MULTIPLIER, per_page ].max
      end

      def normalized_per_page(value)
        value.to_i.clamp(1, MAX_PER_PAGE)
      end

      def normalized_context(value)
        value.to_h.transform_keys(&:to_s).transform_values { |entry| entry.to_s }
      end
    end
  end
end
