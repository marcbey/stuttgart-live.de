require "openai"

module OpenAi
  class ResponsesClient
    class Error < StandardError
      attr_reader :details_payload

      def initialize(message = nil, details_payload: {})
        @details_payload = details_payload.is_a?(Hash) ? details_payload.deep_stringify_keys : {}
        super(message)
      end
    end

    DEFAULT_MODEL = "gpt-5.1".freeze
    DEFAULT_TIMEOUT_SECONDS = 180.0

    attr_reader :model, :temperature, :timeout

    def initialize(model: AppSetting.llm_enrichment_model, temperature: nil, timeout: DEFAULT_TIMEOUT_SECONDS, sdk_client: nil)
      @model = normalize_model(model)
      @temperature = temperature
      @timeout = timeout
      @sdk_client = sdk_client
    end

    def create!(input:, text_format:)
      raise Error, "openai.api_key ist nicht in den Rails Credentials gesetzt." if resolved_api_key.blank?
      raise Error, "llm_enrichment_model ist nicht gesetzt." if model.blank?

      create_with_optional_temperature(
        input: input,
        text_format: text_format,
        include_temperature: temperature.present?
      )
    end

    private

    attr_reader :sdk_client

    def create_with_optional_temperature(input:, text_format:, include_temperature:)
      request = {
        model: model,
        input: input,
        text: {
          format: text_format
        }
      }
      request[:temperature] = temperature if include_temperature

      client.responses.create(**request)
    rescue OpenAI::Errors::Error, StandardError => e
      raise if e.is_a?(Error)

      if include_temperature && unsupported_temperature_error?(e)
        return create_with_optional_temperature(
          input: input,
          text_format: text_format,
          include_temperature: false
        )
      end

      raise build_wrapped_error(e), cause: e
    end

    def client
      @client ||= sdk_client || OpenAI::Client.new(api_key: resolved_api_key, timeout: timeout)
    end

    def resolved_api_key
      @resolved_api_key ||= Rails.application.credentials.dig(:openai, :api_key).to_s.strip.presence
    end

    def credentials_api_key
      resolved_api_key
    end

    def normalize_model(value)
      value.to_s.strip.presence || DEFAULT_MODEL
    end

    def unsupported_temperature_error?(error)
      error.message.to_s.include?("Unsupported parameter: 'temperature'")
    end

    def build_wrapped_error(error)
      Error.new(
        formatted_error_message(error),
        details_payload: error_details_payload(error)
      )
    end

    def formatted_error_message(error)
      case error
      when OpenAI::Errors::AuthenticationError
        prefixed_api_error_message("OpenAI-Authentifizierung fehlgeschlagen", error)
      when OpenAI::Errors::PermissionDeniedError
        prefixed_api_error_message("OpenAI-Zugriff verweigert", error)
      when OpenAI::Errors::RateLimitError
        prefixed_api_error_message(rate_limit_error_label(error), error)
      when OpenAI::Errors::APITimeoutError
        "OpenAI-Request hat das Timeout erreicht: #{error.message}"
      when OpenAI::Errors::APIConnectionError
        "OpenAI-Verbindung fehlgeschlagen: #{error.message}"
      else
        "OpenAI-Request fehlgeschlagen: #{error.message}"
      end
    end

    def prefixed_api_error_message(prefix, error)
      detail = api_error_detail_message(error)
      status_suffix = error.status.present? ? " (HTTP #{error.status})" : ""

      "#{prefix}#{status_suffix}: #{detail}"
    end

    def rate_limit_error_label(error)
      insufficient_quota_error?(error) ? "OpenAI-Kontingent überschritten" : "OpenAI-Rate-Limit erreicht"
    end

    def insufficient_quota_error?(error)
      candidates = [
        error.try(:code),
        error.try(:type),
        error.message
      ].compact.map(&:to_s)

      candidates.any? { |value| value.downcase.include?("quota") || value.downcase.include?("insufficient_quota") }
    end

    def error_details_payload(error)
      payload = { "sdk_error_class" => error.class.to_s }

      if error.is_a?(OpenAI::Errors::APIError)
        normalized_body = normalized_error_body(error.body)

        payload["status"] = error.status if error.status.present?
        payload["code"] = error.try(:code).presence || normalized_body.try(:[], "code").presence
        payload["type"] = error.try(:type).presence || normalized_body.try(:[], "type").presence
        payload["param"] = error.param if error.respond_to?(:param) && error.param.present?
        payload["url"] = error.url.to_s if error.respond_to?(:url) && error.url.present?
        payload["body"] = normalized_body if normalized_body.present?
      end

      payload
    end

    def api_error_detail_message(error)
      body_message = normalized_error_body(error.body)
        .yield_self { |body| body.is_a?(Hash) ? body["message"].to_s.presence : nil }

      body_message || error.message.to_s.presence || error.class.to_s
    end

    def normalized_error_body(body)
      case body
      when Hash
        body.deep_stringify_keys
      when Array
        body
      when nil
        nil
      else
        { "raw" => body.to_s }
      end
    end
  end
end
