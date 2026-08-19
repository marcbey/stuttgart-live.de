require "test_helper"

class Newsletter::SyncIssueToMailjetTest < ActiveSupport::TestCase
  test "creates draft content and marks issue synced" do
    issue = NewsletterIssue.create!(title: "KW 1", subject: "Deine Woche")
    issue.newsletter_issue_items.create!(item: events(:published_one), position: 1)
    client = SuccessfulClient.new

    assert Newsletter::SyncIssueToMailjet.call(issue, client:)

    issue.reload
    assert_equal "synced", issue.status
    assert_equal 12345, issue.mailjet_campaign_draft_id
    assert_nil issue.mailjet_error_message
    assert_equal [ :create_campaign_draft, :update_campaign_content ], client.calls.map(&:first)
  end

  test "updates existing draft metadata before content" do
    issue = NewsletterIssue.create!(
      title: "KW 1",
      subject: "Deine Woche",
      mailjet_campaign_draft_id: 12345
    )
    client = SuccessfulClient.new

    assert Newsletter::SyncIssueToMailjet.call(issue, client:)

    assert_equal [ :update_campaign_draft, :update_campaign_content ], client.calls.map(&:first)
  end

  test "stores mailjet errors" do
    issue = NewsletterIssue.create!(title: "KW 1", subject: "Deine Woche")
    client = FailingClient.new

    assert_not Newsletter::SyncIssueToMailjet.call(issue, client:)

    issue.reload
    assert_equal "failed", issue.status
    assert_includes issue.mailjet_error_message, "unavailable"
  end

  test "syncs interest segment before creating draft" do
    interest = newsletter_interests(:pop)
    interest.update!(mailjet_segment_id: nil)
    issue = NewsletterIssue.create!(title: "Pop KW 1", subject: "Pop", newsletter_interest: interest)
    client = SuccessfulClient.new

    assert Newsletter::SyncIssueToMailjet.call(issue, client:)

    assert_equal [ :ensure_contact_property, :create_contact_segment, :create_campaign_draft, :update_campaign_content ],
                 client.calls.map(&:first)
    assert_equal 4242, interest.reload.mailjet_segment_id
  end

  SuccessfulClient = Struct.new(:calls) do
    def initialize
      super([])
    end

    def create_campaign_draft(issue:)
      calls << [ :create_campaign_draft, issue.id ]
      { "ID" => 12345 }
    end

    def update_campaign_content(draft_id:, html:, text:)
      calls << [ :update_campaign_content, draft_id, html, text ]
      { "ID" => draft_id }
    end

    def update_campaign_draft(issue:, draft_id:)
      calls << [ :update_campaign_draft, issue.id, draft_id ]
      { "ID" => draft_id }
    end

    def ensure_contact_property(name:, data_type:)
      calls << [ :ensure_contact_property, name, data_type ]
      { "ID" => 3131 }
    end

    def create_contact_segment(name:, expression:, description:)
      calls << [ :create_contact_segment, name, expression, description ]
      { "ID" => 4242 }
    end
  end

  FailingClient = Struct.new(:calls) do
    def initialize
      super([])
    end

    def create_campaign_draft(**)
      raise Newsletter::MailjetClient::Error, "unavailable"
    end
  end
end
