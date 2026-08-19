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
end
