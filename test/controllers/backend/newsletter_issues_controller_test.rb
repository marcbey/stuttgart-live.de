require "test_helper"

class Backend::NewsletterIssuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @editor = users(:one)
    @admin = users(:two)
  end

  test "requires authentication" do
    get backend_newsletters_url

    assert_redirected_to new_session_url
  end

  test "editor can create newsletter issue" do
    sign_in_as(@editor)

    assert_difference("NewsletterIssue.count", 1) do
      post backend_newsletters_url, params: {
        newsletter_issue: {
          title: "KW 33",
          subject: "Deine Konzertwoche",
          jump_menu_title: "Wähle dein Genre",
          intro: "Hallo Stuttgart",
          team_tip_profile_key: "sarah-sandner",
          team_tip_text: "Sarah empfiehlt diese Woche kleine Shows."
        }
      }
    end

    issue = NewsletterIssue.order(:created_at).last
    assert_redirected_to backend_newsletter_url(issue)
    assert_equal @editor, issue.created_by
    assert_equal "Wähle dein Genre", issue.jump_menu_title
    assert_equal "Sarah", issue.team_tip_name
    assert_includes issue.team_tip_text, "Sarah empfiehlt"
  end

  test "editor can add event and see preview" do
    sign_in_as(@editor)
    issue = create_issue

    assert_difference("NewsletterIssueItem.count", 1) do
      post backend_newsletter_items_url(issue), params: {
        item_type: "Event",
        item_id: events(:published_one).id
      }
    end

    get backend_newsletter_url(issue)

    assert_response :success
    assert_includes response.body, "Published Event"
    assert_includes response.body, "Newsletter-Vorschau"
  end

  test "editor can add event to selected weekly mix genre" do
    sign_in_as(@editor)
    issue = create_issue(layout_variant: "genre_weekly_mix")
    event = events(:published_one)
    event.genres << genres(:pop)
    event.update!(start_at: 1.week.from_now)

    assert_difference("NewsletterIssueItem.count", 1) do
      post backend_newsletter_items_url(issue), params: {
        item_type: "Event",
        item_id: event.id,
        section_key: genres(:jazz).slug
      }
    end

    item = issue.newsletter_issue_items.order(:created_at).last
    assert_redirected_to backend_newsletter_url(issue)
    assert_equal genres(:jazz).slug, item.section_key
  end

  test "weekly mix event requires explicit genre selection" do
    sign_in_as(@editor)
    issue = create_issue(layout_variant: "genre_weekly_mix")
    event = events(:published_one)
    event.genres << genres(:pop)

    assert_no_difference("NewsletterIssueItem.count") do
      post backend_newsletter_items_url(issue), params: {
        item_type: "Event",
        item_id: event.id,
        section_key: ""
      }
    end

    assert_redirected_to backend_newsletter_url(issue)
    follow_redirect!
    assert_includes response.body, "Bitte ein Genre auswählen"
  end

  test "shows selected items as compact expandable rows" do
    sign_in_as(@editor)
    issue = create_issue
    issue.newsletter_issue_items.create!(item: events(:published_one), position: 1)

    get backend_newsletter_url(issue)

    assert_response :success
    assert_includes response.body, "newsletter-issue-toolbar"
    assert_includes response.body, "newsletter_form_newsletter_issue_#{issue.id}"
    assert_includes response.body, "form=\"newsletter_form_newsletter_issue_#{issue.id}\""
    assert_includes response.body, "Speichern"
    assert_select "a[href='#newsletter-preview']", text: "Vorschau"
    assert_select "#newsletter-preview a[href='#newsletter-editor']", text: "Bearbeiten"
    assert_equal 3, response.body.scan("Hast du vorher gespeichert und den Mailjet-Draft aktualisiert?").length
    assert_includes response.body, "newsletter-item-summary"
    assert_includes response.body, "newsletter-item-editor-body"
    assert_includes response.body, "newsletter-item-summary-remove"
    assert_includes response.body, "Löschen"
    assert_not_includes response.body, "newsletter-danger-zone"
    assert_includes response.body, "Published Artist"
  end

  test "weekly mix editor shows genre placeholder without automatic option" do
    sign_in_as(@editor)
    issue = create_issue(layout_variant: "genre_weekly_mix")
    issue.newsletter_issue_items.create!(item: events(:published_one), position: 1, section_key: genres(:pop).slug)

    get backend_newsletter_url(issue)

    assert_response :success
    assert_includes response.body, "Genre auswählen"
    assert_not_includes response.body, "Automatisch aus Event-Genre"
  end

  test "groups weekly mix selected items by genre in editor" do
    sign_in_as(@editor)
    issue = create_issue(layout_variant: "genre_weekly_mix")
    news = BlogPost.create!(
      title: "Neue Meldung",
      teaser: "Kurz notiert.",
      body: "<p>Text</p>",
      author: @editor,
      status: "published",
      published_at: 1.hour.ago,
      published_by: @editor
    )
    issue.newsletter_issue_items.create!(item: news, position: 1)
    issue.newsletter_issue_items.create!(item: events(:published_one), position: 1, section_key: genres(:rock).slug)

    get backend_newsletter_url(issue)

    assert_response :success
    assert_operator response.body.index("News"), :<, response.body.index("Rock")
    assert_includes response.body, "Rock"
    assert_includes response.body, "newsletter-items-group-title"
    assert_includes response.body, "Genre im Wochenmix"
  end

  test "sorts selected items by newest event date first" do
    sign_in_as(@editor)
    issue = create_issue
    late_item = issue.newsletter_issue_items.create!(item: events(:published_one), position: 1)
    early_item = issue.newsletter_issue_items.create!(item: events(:published_past_one), position: 2)

    post sort_by_date_backend_newsletter_url(issue)

    assert_redirected_to backend_newsletter_url(issue)
    assert_equal 1, late_item.reload.position
    assert_equal 2, early_item.reload.position
  end

  test "lists homepage highlight events before other events" do
    sign_in_as(@editor)
    issue = create_issue
    highlight_event = events(:published_one)
    regular_event = events(:published_past_one)
    highlight_event.update!(highlighted: true)
    regular_event.update!(highlighted: false, promoter_id: "99999", promoter_name: nil)

    get backend_newsletter_url(issue)

    assert_response :success
    highlight_label = "#{highlight_event.artist_name} - #{highlight_event.title}"
    regular_label = "#{regular_event.artist_name} - #{regular_event.title}"
    assert_not_includes response.body, "Highlight - #{highlight_event.title}"
    assert_includes response.body, highlight_label
    assert_operator response.body.index(highlight_label),
                    :<,
                    response.body.index(regular_label)
  end

  test "editor can populate themed newsletter with matching events" do
    sign_in_as(@editor)
    issue = create_issue(newsletter_interest: newsletter_interests(:pop))
    event = events(:published_one)
    event.genres << genres(:pop)
    event.update!(start_at: 2.weeks.from_now, highlighted: true)

    assert_difference("NewsletterIssueItem.count", 1) do
      post populate_from_interest_backend_newsletter_url(issue)
    end

    assert_redirected_to backend_newsletter_url(issue)
    assert_equal event.id, issue.newsletter_issue_items.order(:position).last.item_id
  end

  test "editor can create weekly genre mix draft" do
    sign_in_as(@editor)
    event = events(:published_one)
    event.genres << genres(:pop)
    event.update!(start_at: 1.week.from_now, highlighted: true)

    assert_difference("NewsletterIssue.count", 1) do
      post create_weekly_genre_mix_backend_newsletters_url
    end

    issue = NewsletterIssue.order(:created_at).last
    assert_redirected_to backend_newsletter_url(issue)
    assert_predicate issue, :genre_weekly_mix?
    assert_equal @editor, issue.created_by
    assert_equal event.id, issue.newsletter_issue_items.first.item_id
  end

  test "sync mailjet reports success" do
    sign_in_as(@admin)
    issue = create_issue
    issue.newsletter_issue_items.create!(item: events(:published_one), position: 1)

    with_mailjet_sync_result(true) do
      post sync_mailjet_backend_newsletter_url(issue)
    end

    assert_redirected_to backend_newsletter_url(issue)
    follow_redirect!
    assert_includes response.body, "Mailjet-Draft wurde aktualisiert"
  end

  test "send test reports fixed test address" do
    sign_in_as(@admin)
    issue = create_issue(mailjet_campaign_draft_id: 12345)

    with_mailjet_test_result(true) do
      post send_test_backend_newsletter_url(issue)
    end

    assert_redirected_to backend_newsletter_url(issue)
    follow_redirect!
    assert_includes response.body, "katharinaschopper@russ-live.de"
    assert_includes response.body, "mail@inorange.org"
  end

  test "send test list reports success" do
    sign_in_as(@admin)
    issue = create_issue(mailjet_campaign_draft_id: 12345)

    with_mailjet_test_list_result(true) do
      post send_test_list_backend_newsletter_url(issue)
    end

    assert_redirected_to backend_newsletter_url(issue)
    follow_redirect!
    assert_includes response.body, "Mailjet-Testliste"
  end

  test "final send remains blocked by default" do
    sign_in_as(@admin)
    issue = create_issue(mailjet_campaign_draft_id: 12345)

    post send_now_backend_newsletter_url(issue)

    assert_redirected_to backend_newsletter_url(issue)
    assert_equal "failed", issue.reload.status
    assert_includes issue.mailjet_error_message, "disabled"
  end

  private

  def create_issue(attributes = {})
    NewsletterIssue.create!(
      {
        title: "KW 33",
        subject: "Deine Konzertwoche",
        created_by: @editor
      }.merge(attributes)
    )
  end

  def with_mailjet_sync_result(result)
    original = Newsletter::SyncIssueToMailjet.method(:call)
    Newsletter::SyncIssueToMailjet.singleton_class.define_method(:call) { |_| result }
    yield
  ensure
    Newsletter::SyncIssueToMailjet.singleton_class.define_method(:call, original)
  end

  def with_mailjet_test_result(result)
    original = Newsletter::SendIssueTest.method(:call)
    Newsletter::SendIssueTest.singleton_class.define_method(:call) { |_| result }
    yield
  ensure
    Newsletter::SendIssueTest.singleton_class.define_method(:call, original)
  end

  def with_mailjet_test_list_result(result)
    original = Newsletter::SendIssueTestList.method(:call)
    Newsletter::SendIssueTestList.singleton_class.define_method(:call) { |_, user:| result }
    yield
  ensure
    Newsletter::SendIssueTestList.singleton_class.define_method(:call, original)
  end
end
