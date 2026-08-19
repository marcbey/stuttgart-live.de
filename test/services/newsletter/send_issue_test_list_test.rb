require "test_helper"

class Newsletter::SendIssueTestListServiceTest < ActiveSupport::TestCase
  test "syncs issue and sends campaign to configured test list" do
    issue = NewsletterIssue.create!(
      title: "KW 1",
      subject: "Deine Woche",
      mailjet_campaign_draft_id: 12345
    )
    client = Client.new

    with_mailjet_sync(true) do
      assert Newsletter::SendIssueTestList.call(issue, user: users(:two), client:)
    end

    assert_equal [ 12345 ], client.sent_draft_ids
    assert_equal "tested", issue.reload.status
    assert_equal users(:two), issue.sent_by
  end

  test "blocks test list send when feature flag is disabled" do
    issue = NewsletterIssue.create!(
      title: "KW 1",
      subject: "Deine Woche",
      mailjet_campaign_draft_id: 12345
    )

    with_test_list_send(false) do
      assert_not Newsletter::SendIssueTestList.call(issue, user: users(:two), client: Client.new)
    end

    assert_equal "failed", issue.reload.status
    assert_includes issue.mailjet_error_message, "nicht aktiviert"
  end

  private

  def with_mailjet_sync(result)
    original = Newsletter::SyncIssueToMailjet.method(:call)
    Newsletter::SyncIssueToMailjet.singleton_class.define_method(:call) { |_, client:| result }
    yield
  ensure
    Newsletter::SyncIssueToMailjet.singleton_class.define_method(:call, original)
  end

  def with_test_list_send(value)
    original = AppConfig.method(:newsletter_test_list_send_enabled?)
    AppConfig.singleton_class.send(:define_method, :newsletter_test_list_send_enabled?) { value }
    yield
  ensure
    AppConfig.singleton_class.send(:define_method, :newsletter_test_list_send_enabled?, original)
  end

  Client = Class.new do
    attr_reader :sent_draft_ids

    def initialize
      @sent_draft_ids = []
    end

    def send_campaign_to_test_list(draft_id:)
      sent_draft_ids << draft_id
    end
  end
end
