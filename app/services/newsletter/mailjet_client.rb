require "mailjet"

module Newsletter
  class MailjetClient
    class Error < StandardError; end
    PLACEHOLDER_VALUES = %w[todo tbd changeme change-me replace-me dummy].freeze

    attr_reader :api_key, :secret_key, :list_id, :api_endpoint

    def initialize(
      api_key: AppConfig.mailjet_api_key.to_s.strip,
      secret_key: AppConfig.mailjet_secret_key.to_s.strip,
      list_id: AppConfig.mailjet_list_id.to_s.strip,
      api_endpoint: AppConfig.mailjet_api_endpoint.to_s.strip
    )
      @api_key = api_key
      @secret_key = secret_key
      @list_id = list_id
      @api_endpoint = api_endpoint
    end

    def configured?
      configured_value?(api_key) && configured_value?(secret_key) && configured_value?(list_id)
    end

    def subscribe(email:)
      raise Error, "Mailjet is not configured" unless configured?

      configure_mailjet
      response = Mailjet::Contactslist_managecontact.create(
        id: list_id,
        action: "addnoforce",
        email: email
      )

      normalize_response(response)
    rescue Mailjet::ApiError => error
      raise Error, error.message
    end

    private

    def configure_mailjet
      Mailjet.configure do |config|
        config.api_key = api_key
        config.secret_key = secret_key
        config.end_point = api_endpoint if api_endpoint.present?
      end
    end

    def normalize_response(response)
      attributes = response.respond_to?(:attributes) ? response.attributes : response.to_h

      {
        "ContactID" => attributes["ContactID"] || attributes["contact_id"] || attributes[:contact_id],
        "Email" => attributes["Email"] || attributes["email"] || attributes[:email]
      }.compact
    end

    def configured_value?(value)
      normalized = value.to_s.strip
      normalized.present? && !PLACEHOLDER_VALUES.include?(normalized.downcase)
    end
  end
end
