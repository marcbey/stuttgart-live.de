require "openai"

module OpenAi
  class ResponsesClient
    Error = Class.new(StandardError)
    DEFAULT_MODEL = "gpt-5.1".freeze

    attr_reader :model

    def initialize(model: AppSetting.llm_enrichment_model, sdk_client: nil)
      @model = normalize_model(model)
      @sdk_client = sdk_client
    end

    def create!(input:, text_format:)
      raise Error, "openai.api_key ist nicht in den Rails Credentials gesetzt." if resolved_api_key.blank?
      raise Error, "llm_enrichment_model ist nicht gesetzt." if model.blank?

      response = client.responses.create(
        model: model,
        input: input,
        text: {
          format: text_format
        }
      )

      response
    rescue OpenAI::Errors::Error => e
      raise Error, "OpenAI-Request fehlgeschlagen: #{e.message}"
    rescue StandardError => e
      raise if e.is_a?(Error)

      raise Error, "OpenAI-Request fehlgeschlagen: #{e.message}"
    end

    private

    attr_reader :sdk_client

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
  end
end
