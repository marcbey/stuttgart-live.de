require "test_helper"

class Newsletter::CreateWeeklyGenreMixIssueTest < ActiveSupport::TestCase
  test "creates a weekly genre mix draft and orders selected genre items by date" do
    regular_event = create_published_event(
      slug: "newsletter-pop-regular",
      title: "Pop Regular",
      artist_name: "Pop Regular Artist",
      start_at: 2.days.from_now,
      genre: genres(:pop),
      highlighted: false
    )
    highlight_event = create_published_event(
      slug: "newsletter-pop-highlight",
      title: "Pop Highlight",
      artist_name: "Pop Highlight Artist",
      start_at: 5.days.from_now,
      genre: genres(:pop),
      highlighted: true
    )

    issue = Newsletter::CreateWeeklyGenreMixIssue.call(user: users(:one), today: Time.zone.today)

    assert_predicate issue, :genre_weekly_mix?
    assert_equal users(:one), issue.created_by
    assert_equal "Dein Stuttgart Live Wochenmix", issue.subject
    assert_equal "Für was interessierst du dich? Spring hinein ins Vergnügen :-)", issue.jump_menu_title
    assert_equal "Sarah", issue.team_tip_name
    assert_equal "deine Event-Highlights der Woche, passend zu deinen Interessen und handverlesen statt wahllos zusammengestellt.\nRegelmäßig frisch. Persönlich für dich 🩵",
                 issue.intro
    assert_equal "Mein ganz persönlicher Tipp für euch: Lorem ipsum dolor sit amet, consetetur sadipscing elitr, " \
                 "sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. " \
                 "At vero eos et accusam et justo duo dolores et ea rebum.",
                 issue.team_tip_text
    assert_includes issue.newsletter_issue_items.map(&:item), regular_event
    assert_includes issue.newsletter_issue_items.map(&:item), highlight_event
    assert_equal "pop-indie-singer-songwriter", issue.newsletter_issue_items.find_by!(item: highlight_event).section_key
    assert_operator issue.newsletter_issue_items.find_by!(item: regular_event).position,
                    :<,
                    issue.newsletter_issue_items.find_by!(item: highlight_event).position
  end

  test "limits generated draft to six events per genre" do
    7.times do |index|
      create_published_event(
        slug: "newsletter-rock-#{index}",
        title: "Rock #{index}",
        artist_name: "Rock Artist #{index}",
        start_at: (index + 1).days.from_now,
        genre: genres(:rock)
      )
    end

    issue = Newsletter::CreateWeeklyGenreMixIssue.call(user: users(:one), today: Time.zone.today)
    rock_items = issue.newsletter_issue_items.select { |item| item.item.genres.include?(genres(:rock)) }

    assert_equal 6, rock_items.size
  end

  test "deduplicates event series to the next upcoming date" do
    series = EventSeries.create!(origin: "manual", name: "Mamma Mia")
    later_event = create_published_event(
      slug: "newsletter-mamma-mia-later",
      title: "Mamma Mia",
      artist_name: "Mamma Mia",
      start_at: 2.weeks.from_now,
      genre: genres(:musical),
      event_series: series
    )
    sooner_event = create_published_event(
      slug: "newsletter-mamma-mia-sooner",
      title: "Mamma Mia",
      artist_name: "Mamma Mia",
      start_at: 2.days.from_now,
      genre: genres(:musical),
      event_series: series
    )

    issue = Newsletter::CreateWeeklyGenreMixIssue.call(user: users(:one), today: Time.zone.today)
    series_items = issue.newsletter_issue_items.select { |item| item.item.event_series_id == series.id }

    assert_equal [ sooner_event ], series_items.map(&:item)
    assert_not_includes issue.newsletter_issue_items.map(&:item), later_event
  end

  private

  def create_published_event(slug:, title:, artist_name:, start_at:, genre:, highlighted: false, event_series: nil)
    Event.create!(
      slug:,
      source_fingerprint: "test::#{slug}",
      title:,
      artist_name:,
      normalized_artist_name: artist_name.parameterize,
      start_at:,
      venue_record: venues(:lka_longhorn),
      city: "Stuttgart",
      event_info: "Infos",
      status: "published",
      published_at: 1.day.ago,
      published_by: users(:one),
      completeness_score: 100,
      completeness_flags: [],
      primary_source: "test",
      auto_published: false,
      highlighted:,
      event_series:,
      event_series_assignment: event_series.present? ? "manual" : "auto"
    ).tap { |event| event.genres << genre }
  end
end
