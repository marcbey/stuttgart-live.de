module Importing
  module LlmEnrichment
    class ApiCallRecorder
      MAX_RECORDED_CALLS = 1_000

      def initialize(run:)
        @run = run
      end

      def record(
        provider:,
        operation:,
        status:,
        cached: false,
        event_id: nil,
        started_at: nil,
        finished_at: nil,
        duration_ms: nil,
        request_payload: {},
        response_payload: {},
        error_class: nil,
        error_message: nil
      )
        entry = {
          "provider" => provider.to_s,
          "operation" => operation.to_s,
          "status" => status.to_s,
          "cached" => ActiveModel::Type::Boolean.new.cast(cached),
          "event_id" => event_id,
          "started_at" => format_time(started_at),
          "finished_at" => format_time(finished_at),
          "duration_ms" => duration_ms,
          "request_payload" => normalize_payload(request_payload),
          "response_payload" => normalize_payload(response_payload),
          "error_class" => error_class.to_s.presence,
          "error_message" => error_message.to_s.presence
        }.compact

        run.with_lock do
          metadata = normalized_metadata(run.reload.metadata)
          api_calls = Array(metadata["api_calls"])
          api_calls << entry
          metadata["api_calls"] = api_calls.last(MAX_RECORDED_CALLS)
          run.update_columns(metadata: metadata, updated_at: Time.current)
        end
      end

      private

      attr_reader :run

      def normalized_metadata(metadata)
        metadata.is_a?(Hash) ? metadata.deep_stringify_keys : {}
      end

      def normalize_payload(payload)
        case payload
        when Hash
          payload.deep_stringify_keys
        when nil
          {}
        else
          { "value" => payload.to_s }
        end
      end

      def format_time(value)
        value&.iso8601
      end
    end
  end
end
