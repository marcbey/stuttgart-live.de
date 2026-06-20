module Backend::ImportRunsHelper
  def import_run_json_payload(payload)
    JSON.pretty_generate(payload.is_a?(Hash) ? payload : {})
  rescue JSON::GeneratorError
    payload.to_s
  end

  def import_run_api_calls(run)
    metadata = run.metadata.is_a?(Hash) ? run.metadata.deep_stringify_keys : {}
    Array(metadata["api_calls"]).select { |entry| entry.is_a?(Hash) }.map(&:deep_stringify_keys)
  end

  def import_run_api_call_cache_label(api_call)
    ActiveModel::Type::Boolean.new.cast(api_call["cached"]) ? "Cache-Hit" : "Extern"
  end

  def import_run_api_call_time_label(api_call, key)
    raw_value = api_call[key].to_s.strip
    return "-" if raw_value.blank?

    Time.zone.parse(raw_value).strftime("%d.%m.%Y %H:%M:%S")
  rescue ArgumentError
    raw_value
  end

  def import_run_api_call_duration_label(api_call)
    duration_ms = Integer(api_call["duration_ms"], exception: false)
    return "-" if duration_ms.blank?

    "#{duration_ms} ms"
  end

  def import_run_api_call_payload(api_call)
    {
      request: api_call["request_payload"].presence || {},
      response: api_call["response_payload"].presence || {},
      error: {
        class: api_call["error_class"],
        message: api_call["error_message"]
      }.compact
    }.compact
  end
end
