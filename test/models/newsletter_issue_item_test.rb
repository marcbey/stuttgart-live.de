require "test_helper"

class NewsletterIssueItemTest < ActiveSupport::TestCase
  test "requires section key for weekly mix event items" do
    issue = NewsletterIssue.create!(
      title: "Wochenmix",
      subject: "Dein Wochenmix",
      layout_variant: "genre_weekly_mix",
      created_by: users(:one)
    )
    item = issue.newsletter_issue_items.build(item: events(:published_one), position: 1)

    assert_not item.valid?
    assert_includes item.errors[:section_key], "muss ausgewählt werden"
  end

  test "allows selected header genre for weekly mix event items" do
    issue = NewsletterIssue.create!(
      title: "Wochenmix",
      subject: "Dein Wochenmix",
      layout_variant: "genre_weekly_mix",
      created_by: users(:one)
    )
    item = issue.newsletter_issue_items.build(
      item: events(:published_one),
      position: 1,
      section_key: genres(:pop).slug
    )

    assert_predicate item, :valid?
  end

  test "uses event title as default teaser without venue and city" do
    event = events(:published_one)
    event.update!(title: "Die große Tour", city: "Stuttgart")
    issue = NewsletterIssue.create!(title: "KW 1", subject: "Deine Woche", created_by: users(:one))
    item = issue.newsletter_issue_items.create!(item: event, position: 1)

    assert_equal "Die große Tour", item.display_teaser
    assert_not_includes item.display_teaser, event.venue
    assert_not_includes item.display_teaser, "Stuttgart"
  end
end
