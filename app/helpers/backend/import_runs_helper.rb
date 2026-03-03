module Backend::ImportRunsHelper
  def import_run_json_payload(payload)
    JSON.pretty_generate(payload.is_a?(Hash) ? payload : {})
  rescue JSON::GeneratorError
    payload.to_s
  end
end
