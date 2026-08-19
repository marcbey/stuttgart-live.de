require "mail"
require "mailjet"

module Newsletter
  class MailjetClient
    class Error < StandardError; end
    TEST_RECIPIENTS = [
      { "Email" => "katharinaschopper@russ-live.de", "Name" => "Katharina Schopper" }.freeze,
      { "Email" => "mail@inorange.org", "Name" => "mail@inorange.org" }.freeze
    ].freeze
    TEST_EMAILS = TEST_RECIPIENTS.map { |recipient| recipient.fetch("Email") }.freeze
    TEST_EMAIL = TEST_EMAILS.first
    DEFAULT_SENDER_NAME = "Stuttgart Live"
    PLACEHOLDER_VALUES = %w[todo tbd changeme change-me replace-me dummy].freeze
    MAILJET_ERRORS = [ Mailjet::ApiError, Mailjet::Error ].freeze

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
      api_configured? && configured_value?(list_id)
    end

    def api_configured?
      configured_value?(api_key) && configured_value?(secret_key)
    end

    def subscribe(email:, properties: {})
      raise Error, "Mailjet is not configured" unless configured?

      configure_mailjet
      response = Mailjet::Contactslist_managecontact.create({
        id: list_id,
        action: "addnoforce",
        email: email,
        properties: properties.presence
      }.compact)

      normalize_response(response)
    rescue *MAILJET_ERRORS => error
      raise Error, error.message
    end

    def ensure_contact_property(name:, data_type:)
      raise Error, "Mailjet is not configured" unless configured?

      configure_mailjet
      existing = Mailjet::Contactmetadata.all(name: name).first
      return normalize_response(existing) if existing.present?

      response = Mailjet::Contactmetadata.create(
        name: name,
        datatype: data_type,
        namespace: "static"
      )
      normalize_response(response)
    rescue *MAILJET_ERRORS => error
      raise Error, error.message
    end

    def create_contact_segment(name:, expression:, description:)
      raise Error, "Mailjet is not configured" unless configured?

      configure_mailjet
      existing = Mailjet::Contactfilter.all(name: name).first
      return normalize_response(existing) if existing.present?

      response = Mailjet::Contactfilter.create(
        name: name,
        expression: expression,
        description: description
      )
      normalize_response(response)
    rescue *MAILJET_ERRORS => error
      raise Error, error.message
    end

    def send_transactional_email(to:, subject:, html:, text:)
      raise Error, "Mailjet is not configured" unless api_configured?

      configure_mailjet
      from_email = transactional_sender_email

      configure_mailjet(api_version: "v3.1")
      response = Mailjet::Send.create(
        messages: [
          {
            "From" => {
              "Email" => from_email,
              "Name" => sender_name
            },
            "To" => [
              {
                "Email" => to
              }
            ],
            "Subject" => subject,
            "TextPart" => text,
            "HTMLPart" => html
          }
        ]
      )
      normalize_response(response)
    rescue *MAILJET_ERRORS => error
      raise Error, error.message
    end

    def create_campaign_draft(issue:)
      raise Error, "Mailjet is not configured" unless configured?

      configure_mailjet
      response = Mailjet::Campaigndraft.create(campaign_draft_attributes(issue))
      normalize_response(response)
    rescue *MAILJET_ERRORS => error
      raise Error, error.message
    end

    def update_campaign_content(draft_id:, html:, text:)
      raise Error, "Mailjet is not configured" unless configured?

      configure_mailjet
      response = Mailjet::Campaigndraft_detailcontent.create(
        id: draft_id,
        html_part: html,
        text_part: text
      )
      normalize_response(response)
    rescue *MAILJET_ERRORS => error
      raise Error, error.message
    end

    def update_campaign_draft(issue:, draft_id:)
      raise Error, "Mailjet is not configured" unless configured?

      configure_mailjet
      draft = Mailjet::Campaigndraft.new(campaign_draft_attributes(issue).merge(id: draft_id, persisted: true))
      draft.save!
      normalize_response(draft)
    rescue *MAILJET_ERRORS => error
      raise Error, error.message
    end

    def send_campaign_test(draft_id:)
      raise Error, "Mailjet is not configured" unless configured?

      configure_mailjet
      response = Mailjet::Campaigndraft_test.create(
        id: draft_id,
        recipients: test_recipients
      )
      normalize_response(response)
    rescue *MAILJET_ERRORS => error
      raise Error, error.message
    end

    def send_campaign(draft_id:)
      raise Error, "Final newsletter send is disabled" unless AppConfig.newsletter_final_send_enabled?

      perform_campaign_send(draft_id:)
    end

    def send_campaign_to_test_list(draft_id:)
      perform_campaign_send(draft_id:)
    end

    private

    def perform_campaign_send(draft_id:)
      raise Error, "Mailjet is not configured" unless configured?

      configure_mailjet
      response = Mailjet::Campaigndraft_send.create(id: draft_id)
      normalize_response(response)
    rescue *MAILJET_ERRORS => error
      raise Error, error.message
    end

    def configure_mailjet(api_version: "v3")
      Mailjet.configure do |config|
        config.api_key = api_key
        config.secret_key = secret_key
        config.api_version = api_version
        config.end_point = api_endpoint if api_endpoint.present?
      end
    end

    def test_recipients
      TEST_RECIPIENTS.map(&:dup)
    end

    def normalize_response(response)
      attributes = response.respond_to?(:attributes) ? response.attributes : response.to_h
      attributes = attributes["Data"].first if attributes["Data"].is_a?(Array) && attributes["Data"].first.present?

      {
        "ID" => attributes["ID"] || attributes["id"] || attributes[:id],
        "ContactID" => attributes["ContactID"] || attributes["contact_id"] || attributes[:contact_id],
        "Email" => attributes["Email"] || attributes["email"] || attributes[:email]
      }.compact
    end

    def campaign_draft_attributes(issue)
      {
        title: issue.title,
        subject: issue.subject,
        locale: "de_DE",
        edit_mode: "html2",
        is_text_part_included: true,
        "ContactsListID" => numeric_list_id,
        "SegmentationID" => issue.newsletter_interest&.mailjet_segment_id,
        "Sender" => mailjet_sender_id,
        sender_email: sender_email,
        sender_name: sender_name,
        reply_email: sender_email
      }.compact
    end

    def numeric_list_id
      return list_id.to_i if list_id.match?(/\A\d+\z/)

      list_id
    end

    def sender_email
      return configured_sender_email if configured_sender_id.present?

      sender_attribute(active_sender, :email).presence || sender_address.address
    end

    def sender_name
      sender_address.display_name.presence || DEFAULT_SENDER_NAME
    end

    def transactional_sender_email
      sender_attribute(active_sender, :email).presence || configured_sender_email
    end

    def mailjet_sender_id
      configured_sender_id || active_sender_id
    end

    def configured_sender_id
      value = AppConfig.mailjet_sender.to_s.strip
      return if value.blank?
      return value.to_i if value.match?(/\A\d+\z/)

      Rails.logger.warn("Ignoring non-numeric MAILJET_SENDER value for newsletter campaign drafts")
      nil
    end

    def active_sender_id
      sender = active_sender
      raise Error, "No active Mailjet sender found in Mailjet" if sender.blank?

      id = sender_attribute(sender, :id)
      return id if id.present?

      raise Error, "No active Mailjet sender found in Mailjet"
    end

    def active_sender
      @active_sender ||= begin
        senders = active_mailjet_senders
        senders.find { |sender| sender_attribute(sender, :email).to_s.casecmp?(configured_sender_email) } || senders.first
      end
    rescue *MAILJET_ERRORS => error
      raise Error, error.message
    end

    def active_mailjet_senders
      Mailjet::Sender.all(email: configured_sender_email, status: "Active").presence ||
        Mailjet::Sender.all(status: "Active")
    end

    def sender_attribute(sender, key)
      return if sender.blank?

      attributes = sender.respond_to?(:attributes) ? sender.attributes : sender.to_h
      attributes[key] || attributes[key.to_s] || attributes[key.to_s.camelcase]
    end

    def configured_sender_email
      sender_address.address
    end

    def sender_address
      @sender_address ||= Mail::Address.new(sender_from_value)
    rescue Mail::Field::ParseError
      Mail::Address.new("newsletter@stuttgart-live.de")
    end

    def sender_from_value
      AppConfig.mailer_from.to_s.strip.presence || "newsletter@stuttgart-live.de"
    end

    def configured_value?(value)
      normalized = value.to_s.strip
      normalized.present? && !PLACEHOLDER_VALUES.include?(normalized.downcase)
    end
  end
end
