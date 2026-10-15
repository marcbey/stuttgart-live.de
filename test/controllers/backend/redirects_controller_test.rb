require "test_helper"

class Backend::RedirectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:two)
    @event = events(:published_one)
    @destination = event_path(@event.slug)
  end

  test "admin sees the Pages inbox conventions and backend assets" do
    sign_in_as(@admin)
    rule = create_rule(source_path: "/old-event", source_metadata: { title: "Alter Titel", provider_id: "123" })

    get "/backend/redirects"

    assert_response :success
    assert_select ".app-nav-links .app-nav-link-active", text: "Weiterleitungen"
    assert_select ".backend-shell.backend-inbox-shell[data-controller='editor-inbox']"
    assert_select "#redirects_list"
    assert_select "turbo-frame#redirect_editor"
    assert_select "#redirect_topbar_editor_actions button", text: "Save"
    assert_select "a.button", text: "New", count: 1
    assert_select "link[href*='backend']"
    assert_select "#redirects_list", text: /#{Regexp.escape(rule.source_path)}/
    assert_includes response.body, "tatsächlichen 404"
  end

  test "guests editors and bloggers cannot manage redirects" do
    get "/backend/redirects"
    assert_redirected_to new_session_url

    sign_in_as(users(:one))
    get "/backend/redirects"
    assert_redirected_to backend_root_url

    sign_in_as(users(:blogger))
    get "/backend/redirects"
    assert_redirected_to root_url
  end

  test "new and edit preserve context and provide frame action templates" do
    sign_in_as(@admin)
    rule = create_rule
    context = { query: "Alt", status: "unresolved", origin: "automatic", page: 2 }

    get new_backend_redirect_url(context)
    assert_redirected_to backend_redirects_url(context.merge(new: "1"))
    follow_redirect!
    assert_select "a.button", text: "New", count: 0
    assert_select "#redirect_topbar_editor_actions a", text: "Cancel"
    assert_select "select[name='legacy_redirect[status]'] option[selected][value='redirect']"

    get edit_backend_redirect_url(rule, context), headers: { "Turbo-Frame" => "redirect_editor" }
    assert_response :success
    assert_select "turbo-frame#redirect_editor .editor-panel[data-selected-item-id='#{rule.id}']"
    assert_select "template.editor-actions-template"
    assert_select "input[name='page'][value='2']"
    assert_select "input[name='origin'][value='automatic']"
  end

  test "frame selection owns the selected redirect submitted with filters" do
    sign_in_as(@admin)
    first = create_rule
    selected = create_rule

    get edit_backend_redirect_url(selected, page: 2), headers: { "Turbo-Frame" => "redirect_editor" }

    assert_response :success
    assert_select "turbo-frame#redirect_editor > input[name='redirect_id'][value='#{selected.id}'][form='redirect_filters']", count: 1
    assert_select "form.editor-form input[name='redirect_id']", count: 0

    get backend_redirects_url(redirect_id: first.id)

    assert_response :success
    assert_select "form#redirect_filters", count: 1
    assert_select "form.filter-form input[name='redirect_id']", count: 0
    assert_select "turbo-frame#redirect_editor > input[name='redirect_id'][value='#{first.id}'][form='redirect_filters']", count: 1
  end

  test "filters search title source and destination with pagination and selection context" do
    sign_in_as(@admin)
    26.times { |index| create_rule(source_path: "/archive-#{index.to_s.rjust(2, '0')}", source_metadata: { title: "Konzert Archiv" }) }
    create_rule(source_path: "/different", status: "disabled", origin: "manual")

    get backend_redirects_url(query: "KONZERT", status: "unresolved", origin: "automatic", page: 2)
    assert_response :success
    assert_select "#redirects_list .redirect-list-item", count: 1
    assert_select ".event-list-count strong", text: "26"
    assert_select "#redirects_list a.redirect-link[href*='page=2'][href*='origin=automatic'][href*='status=unresolved']"
    assert_select "#redirects_list a[data-editor-inbox-selection-url*='redirect_id=']"

    get backend_redirects_url(page: -5)
    assert_select "#redirects_list .redirect-list-item", count: 25
    assert_select "input[name='page'][value='1']"

    rule = create_rule(source_path: "/other-source", status: "redirect", origin: "manual", destination: "/events")
    get backend_redirects_url(query: "/events", redirect_id: rule.id)
    assert_select "#redirects_list .redirect-list-item", count: 1
  end

  test "create sets manual origin and retains filters even when saved row no longer matches" do
    sign_in_as(@admin)

    assert_difference -> { LegacyRedirect.count }, 1 do
      post backend_redirects_url, params: {
        query: "missing", status: "unresolved", origin: "automatic", page: 2,
        legacy_redirect: { source_path: "/old-concert", source_kind: "event", status: "redirect", destination: @destination, origin: "automatic" }
      }
    end

    rule = LegacyRedirect.find_by!(source_path: "/old-concert")
    assert_equal "manual", rule.origin
    assert_equal @event, rule.target
    assert_redirected_to backend_redirects_url(query: "missing", status: "unresolved", origin: "automatic", page: 2, redirect_id: rule.id)
    follow_redirect!
    assert_select "#redirects_list .redirect-list-item", count: 0
    assert_select "#redirect_editor .editor-panel[data-selected-item-id='#{rule.id}']"
  end

  test "turbo create replaces the entire topbar with persisted actions and New" do
    sign_in_as(@admin)

    post backend_redirects_url, params: {
      query: "old", status: "redirect", origin: "manual", page: 2,
      legacy_redirect: { source_path: "/old-topbar", source_kind: "event", status: "redirect", destination: @destination }
    }, as: :turbo_stream

    assert_response :success
    rule = LegacyRedirect.find_by!(source_path: "/old-topbar")
    assert_select "turbo-stream[action='replace'][target='redirect_topbar_controls'] template" do
      assert_select "#redirect_topbar_controls button[form='editor_form_legacy_redirect_#{rule.id}']", text: "Save"
      assert_select "a[href='#{@destination}']", text: "Open"
      assert_select "form[action*='#{recheck_backend_redirect_path(rule)}'] button", text: "Prüfen"
      assert_select "a[href*='/backend/redirects/new'][href*='page=2'][href*='origin=manual']", text: "New"
      assert_select "a", text: "Cancel", count: 0
    end
  end

  test "invalid destination and source retain submitted raw input and context" do
    sign_in_as(@admin)
    rule = create_rule

    patch backend_redirect_url(rule), params: {
      query: "archive", status: "unresolved", origin: "automatic", page: 3,
      legacy_redirect: { source_path: "https://external.example/invalid", source_kind: "event", status: "redirect", destination: "https://evil.example/target" }
    }

    assert_response :unprocessable_entity
    assert_select "input[name='legacy_redirect[destination]'][value='https://evil.example/target']"
    assert_select "input[name='legacy_redirect[source_path]'][value='https://external.example/invalid']"
    assert_select "input[name='query'][value='archive']"
    assert_select "input[name='page'][value='3']"
    assert_equal "unresolved", rule.reload.status
  end

  test "hidden and self destinations are rejected" do
    sign_in_as(@admin)
    rule = create_rule(source_path: @destination)

    [ @destination, event_path(events(:needs_review_one).slug) ].each do |destination|
      patch backend_redirect_url(rule), params: { legacy_redirect: { status: "redirect", destination: destination } }, as: :turbo_stream
      assert_response :unprocessable_entity
      assert_includes response.body, 'target="redirect_editor"'
      assert_includes response.body, 'target="flash-messages"'
    end
    assert_equal "unresolved", rule.reload.status
  end

  test "disable retains audit metadata and automatic mode clears old decisions" do
    sign_in_as(@admin)
    rule = create_rule(status: "redirect", origin: "automatic", destination: @destination, source_metadata: { title: "Audit" }, checked_at: Time.current)

    patch backend_redirect_url(rule), params: { legacy_redirect: { status: "disabled", destination: @destination } }, as: :turbo_stream
    assert_response :success
    assert_equal "disabled", rule.reload.status
    assert_equal "manual", rule.origin
    assert_equal "Audit", rule.source_metadata["title"]
    assert_includes response.body, 'target="redirects_list"'

    patch backend_redirect_url(rule), params: { legacy_redirect: { status: "unresolved", destination: @destination } }
    assert_equal "automatic", rule.reload.origin
    assert_nil rule.target
    assert_nil rule.target_path
    assert_nil rule.checked_at
  end

  test "recheck evaluates automatic rules and preserves manual decisions" do
    sign_in_as(@admin)
    automatic = create_rule(source_path: "/automatic-old", checked_at: 1.minute.ago)
    manual = create_rule(source_path: "/manual-old", status: "redirect", origin: "manual", destination: @destination)

    post recheck_backend_redirect_url(automatic), params: { query: "old", status: "unresolved", origin: "automatic", page: 2 }
    assert_redirected_to backend_redirects_url(query: "old", status: "unresolved", origin: "automatic", page: 2, redirect_id: automatic.id)
    assert automatic.reload.checked_at > 30.seconds.ago

    post recheck_backend_redirect_url(manual), as: :turbo_stream
    assert_response :success
    assert_equal "manual", manual.reload.origin
    assert_equal @destination, manual.destination
    assert_equal "redirect", manual.status
  end

  test "recheck repairs an automatic rule whose destination became hidden" do
    sign_in_as(@admin)
    rule = create_rule(status: "redirect", origin: "automatic", destination: @destination)
    @event.update!(status: "needs_review", published_at: nil)

    post recheck_backend_redirect_url(rule)

    assert_response :redirect
    assert_equal "unresolved", rule.reload.status
    assert_nil rule.target
  end

  test "long source URLs use escaped wrapping markup" do
    sign_in_as(@admin)
    rule = create_rule(source_path: "/#{'long-segment' * 30}", source_metadata: { title: "<script>alert(1)</script>" })

    get backend_redirects_url(redirect_id: rule.id)

    assert_select ".redirect-url", text: rule.source_path
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  private

    def create_rule(**attributes)
      LegacyRedirect.create!({ source_path: "/old-#{SecureRandom.hex(6)}", source_kind: "event" }.merge(attributes))
    end
end
