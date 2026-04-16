require "openai"

module OpenAi
  class ResponsesClient
    Error = Class.new(StandardError)
    DEFAULT_MODEL = "gpt-5.1".freeze

    attr_reader :model, :temperature

    def initialize(model: AppSetting.llm_enrichment_model, temperature: nil, sdk_client: nil)
      @model = normalize_model(model)
      @temperature = temperature
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

      raise Error, "OpenAI-Request fehlgeschlagen: #{e.message}"
    end

    def client
      @client ||= sdk_client || OpenAI::Client.new(api_key: resolved_api_key)
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
  end
end
