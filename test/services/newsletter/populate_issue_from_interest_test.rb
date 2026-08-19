require "test_helper"

class Newsletter::PopulateIssueFromInterestTest < ActiveSupport::TestCase
  test "adds upcoming events for selected interest without removing existing items" do
    issue = NewsletterIssue.create!(
      title: "Pop KW 33",
      subject: "Pop Highlights",
      newsletter_interest: newsletter_interests(:pop)
    )
    existing_item = issue.newsletter_issue_items.create!(item: events(:published_past_one), position: 1)
    pop_event = events(:published_one)
    pop_event.genres << genres(:pop)
    pop_event.update!(start_at: 2.weeks.from_now, highlighted: true)

    assert_difference("NewsletterIssueItem.count", 1) do
      assert_equal 1, Newsletter::PopulateIssueFromInterest.call(issue)
    end

    assert_equal existing_item.id, issue.newsletter_issue_items.order(:position).first.id
    assert_equal pop_event.id, issue.newsletter_issue_items.order(:position).last.item_id
  end

  test "returns zero for general newsletters" do
    issue = NewsletterIssue.create!(title: "KW 33", subject: "Alle Highlights")

    assert_no_difference("NewsletterIssueItem.count") do
      assert_equal 0, Newsletter::PopulateIssueFromInterest.call(issue)
    end
  end
end
