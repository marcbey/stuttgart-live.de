require "test_helper"

class Newsletter::SendIssueServiceTest < ActiveSupport::TestCase
  test "blocks final send when feature flag is disabled" do
    issue = NewsletterIssue.create!(
      title: "KW 1",
      subject: "Deine Woche",
      mailjet_campaign_draft_id: 12345
    )

    with_final_send(false) do
      assert_not Newsletter::SendIssue.call(issue, user: users(:two), client: Client.new)
    end

    assert_equal "failed", issue.reload.status
    assert_includes issue.mailjet_error_message, "disabled"
  end

  test "refreshes draft safety settings immediately before final send" do
    issue = NewsletterIssue.create!(title: "Versand", subject: "News", mailjet_campaign_draft_id: 12345)
    client = SendingClient.new
    with_final_send(true) do
      assert Newsletter::SendIssue.call(issue, user: users(:two), client:)
    end
    assert_equal [ :metadata, :content, :send ], client.calls
    assert_equal "sent", issue.reload.status
  end

  test "never sends if refreshing draft content fails" do
    issue = NewsletterIssue.create!(title: "Versand", subject: "News", mailjet_campaign_draft_id: 12345)
    client = SendingClient.new(fail_content: true)
    with_final_send(true) do
      assert_not Newsletter::SendIssue.call(issue, user: users(:two), client:)
    end
    assert_equal [ :metadata, :content ], client.calls
    assert_equal "failed", issue.reload.status
  end

  private

  def with_final_send(value)
    original_method = AppConfig.method(:newsletter_final_send_enabled?)
    AppConfig.singleton_class.send(:define_method, :newsletter_final_send_enabled?) { value }
    yield
  ensure
    AppConfig.singleton_class.send(:define_method, :newsletter_final_send_enabled?, original_method)
  end

  Client = Class.new do
    def send_campaign(draft_id:); end
  end

  class SendingClient
    attr_reader :calls

    def initialize(fail_content: false)
      @fail_content = fail_content
      @calls = []
    end

    def update_campaign_draft(**)
      calls << :metadata
      { "ID" => 12345 }
    end

    def update_campaign_content(**)
      calls << :content
      raise Newsletter::MailjetClient::Error, "unavailable" if @fail_content

      { "ID" => 12345 }
    end

    def send_campaign(**)
      calls << :send
    end
  end
end
