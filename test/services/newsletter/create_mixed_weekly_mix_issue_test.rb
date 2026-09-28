require "test_helper"

class Newsletter::CreateMixedWeeklyMixIssueTest < ActiveSupport::TestCase
  test "creates one mixed section with ten events and prefers highlights" do
    regular_events = 10.times.map do |index|
      create_published_event(
        slug: "mixed-regular-#{index}",
        start_at: (index + 1).days.from_now,
        genre: index.even? ? genres(:rock) : genres(:jazz)
      )
    end
    highlight = create_published_event(
      slug: "mixed-highlight",
      start_at: 10.days.from_now,
      genre: genres(:pop),
      highlighted: true
    )

    issue = Newsletter::CreateMixedWeeklyMixIssue.call(user: users(:one), today: Time.zone.today)

    assert_predicate issue, :mixed_weekly_mix?
    assert issue.title.start_with?("Wochenmix KW ")
    assert_equal 10, issue.newsletter_issue_items.size
    assert_equal highlight, issue.newsletter_issue_items.first.item
    assert_not_includes issue.newsletter_issue_items.map(&:item), regular_events.last
    assert issue.newsletter_issue_items.all? { |item| item.section_key.present? }
  end

  private

  def create_published_event(slug:, start_at:, genre:, highlighted: false)
    Event.create!(
      slug:,
      source_fingerprint: "test::#{slug}",
      title: slug.humanize,
      artist_name: slug.humanize,
      normalized_artist_name: slug,
      start_at:,
      venue_record: venues(:lka_longhorn),
      city: "Stuttgart",
      event_info: "Infos",
      status: "published",
      published_at: 1.day.ago,
      published_by: users(:one),
      highlighted:,
      completeness_score: 100,
      completeness_flags: [],
      primary_source: "test",
      auto_published: false
    ).tap { |event| event.genres << genre }
  end
end
