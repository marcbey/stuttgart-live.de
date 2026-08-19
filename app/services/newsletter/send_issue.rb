module Newsletter
  class SendIssue
    def self.call(issue, user:, client: MailjetClient.new)
      new(issue, user:, client:).call
    end

    def initialize(issue, user:, client: MailjetClient.new)
      @issue = issue
      @user = user
      @client = client
    end

    def call
      raise MailjetClient::Error, "Final newsletter send is disabled" unless AppConfig.newsletter_final_send_enabled?

      client.send_campaign(draft_id: issue.mailjet_campaign_draft_id)
      issue.update!(status: "sent", sent_at: Time.current, sent_by: user, mailjet_error_message: nil)
      true
    rescue MailjetClient::Error => error
      issue.mark_mailjet_failed!(error.message)
      false
    end

    private

    attr_reader :issue, :user, :client
  end
end
