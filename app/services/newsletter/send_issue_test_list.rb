module Newsletter
  class SendIssueTestList
    def self.call(issue, user:, client: MailjetClient.new)
      new(issue, user:, client:).call
    end

    def initialize(issue, user:, client: MailjetClient.new)
      @issue = issue
      @user = user
      @client = client
    end

    def call
      ensure_enabled!
      return false unless ensure_synced

      client.send_campaign_to_test_list(draft_id: issue.mailjet_campaign_draft_id)
      issue.update!(status: "tested", test_sent_at: Time.current, sent_by: user, mailjet_error_message: nil)
      true
    rescue MailjetClient::Error => error
      issue.mark_mailjet_failed!(error.message)
      false
    end

    private

    attr_reader :issue, :user, :client

    def ensure_enabled!
      return if AppConfig.newsletter_test_list_send_enabled?

      raise MailjetClient::Error, "Mailjet-Testlistenversand ist nicht aktiviert"
    end

    def ensure_synced
      SyncIssueToMailjet.call(issue, client:)
    end
  end
end
