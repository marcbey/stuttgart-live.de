module Newsletter
  class SendIssueTest
    def self.call(issue, client: MailjetClient.new)
      new(issue, client:).call
    end

    def initialize(issue, client: MailjetClient.new)
      @issue = issue
      @client = client
    end

    def call
      return false unless ensure_synced

      client.send_campaign_test(draft_id: issue.mailjet_campaign_draft_id)
      issue.mark_test_sent!
      true
    rescue MailjetClient::Error => error
      issue.mark_mailjet_failed!(error.message)
      false
    end

    private

    attr_reader :issue, :client

    def ensure_synced
      SyncIssueToMailjet.call(issue, client:)
    end
  end
end
