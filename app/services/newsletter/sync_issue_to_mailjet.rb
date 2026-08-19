module Newsletter
  class SyncIssueToMailjet
    def self.call(issue, client: MailjetClient.new)
      new(issue, client:).call
    end

    def initialize(issue, client: MailjetClient.new)
      @issue = issue
      @client = client
    end

    def call
      sync_interest_segment
      rendered = Renderer.call(issue)
      draft_id = issue.mailjet_campaign_draft_id || create_draft_id
      update_draft_metadata(draft_id) if issue.mailjet_campaign_draft_id.present?
      client.update_campaign_content(draft_id:, html: rendered.html, text: rendered.text)
      issue.mark_mailjet_synced!(draft_id:)
      true
    rescue MailjetClient::Error => error
      issue.mark_mailjet_failed!(error.message)
      false
    end

    private

    attr_reader :issue, :client

    def sync_interest_segment
      return if issue.newsletter_interest.blank?

      SyncInterestToMailjet.call(issue.newsletter_interest, client:)
    end

    def create_draft_id
      response = client.create_campaign_draft(issue:)
      response.fetch("ID")
    end

    def update_draft_metadata(draft_id)
      return unless client.respond_to?(:update_campaign_draft)

      client.update_campaign_draft(issue:, draft_id:)
    end
  end
end
