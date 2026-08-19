require "test_helper"

class Newsletter::SendIssueTestTest < ActiveSupport::TestCase
  test "sends test to fixed mailjet test address" do
    issue = NewsletterIssue.create!(
      title: "KW 1",
      subject: "Deine Woche",
      mailjet_campaign_draft_id: 12345
    )
    client = SuccessfulClient.new

    assert Newsletter::SendIssueTest.call(issue, client:)

    assert_equal [ 12345 ], client.synced_draft_ids
    assert_equal [ 12345 ], client.test_draft_ids
    assert_equal "tested", issue.reload.status
  end

  SuccessfulClient = Struct.new(:synced_draft_ids, :test_draft_ids) do
    def initialize
      super([], [])
    end

    def update_campaign_draft(issue:, draft_id:)
      synced_draft_ids << draft_id
      { "ID" => draft_id }
    end

    def update_campaign_content(draft_id:, html:, text:)
      { "ID" => draft_id }
    end

    def send_campaign_test(draft_id:)
      test_draft_ids << draft_id
      { "ID" => draft_id }
    end
  end
end
