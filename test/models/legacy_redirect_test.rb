require "test_helper"

class LegacyRedirectTest < ActiveSupport::TestCase
  test "normalizes unique sources and validates source identities" do
    rule = LegacyRedirect.create!(source_path: "https://stuttgart-live.de/Alt/?utm_source=x")
    assert_equal "/Alt", rule.source_path
    assert_equal "unresolved", rule.status
    assert_not LegacyRedirect.new(source_path: "/Alt/").valid?
    assert_not LegacyRedirect.new(source_path: "/backend/a").valid?
    assert_not LegacyRedirect.new(source_path: "/a?p=42").valid?
  end

  test "resolves manual destinations to public records and follows current slug" do
    event = events(:published_one)
    rule = LegacyRedirect.create!(source_path: "/old-event", status: "redirect", origin: "manual", destination: "/events/published-event")
    assert_equal event, rule.target
    assert_nil rule.target_path
    event.update!(slug: "new-public-slug")
    assert_equal "/events/new-public-slug", rule.destination
    event.update_columns(status: "needs_review")
    assert_nil rule.destination
    assert_not rule.valid?
  end

  test "rejects unsafe missing self and chained destinations" do
    [ "/not-a-known-page", "/backend", "//evil.test/a", "/events/needs-review-event", "/old" ].each do |destination|
      assert_not LegacyRedirect.new(source_path: "/old", status: "redirect", destination: destination).valid?, destination
    end
    LegacyRedirect.create!(source_path: "/highlights", status: "redirect", destination: "/news")
    assert_not LegacyRedirect.new(source_path: "/older", status: "redirect", destination: "/highlights").valid?
    incoming = LegacyRedirect.create!(source_path: "/incoming", status: "redirect", destination: "/unter-30")
    assert_not LegacyRedirect.new(source_path: incoming.destination, status: "redirect", destination: "/news").valid?
  end

  test "preserves invalid entered source through repeated failed validations" do
    [ "/old?p=42", "https://other.example/old" ].each do |source|
      rule = LegacyRedirect.new(source_path: source, status: "redirect", destination: "/news")
      2.times do
        assert_not rule.valid?
        assert_equal source, rule.source_path
      end
    end
  end

  test "normalizes directly assigned fixed destinations before checking incoming chains" do
    [ "/unter-30/", "https://www.stuttgart-live.de/unter-30", "/unter-30?utm_source=archive" ].each_with_index do |path, index|
      incoming = LegacyRedirect.create!(source_path: "/old-#{index}", status: "redirect", target_path: path)
      assert_equal "/unter-30", incoming.reload.target_path
      chained = LegacyRedirect.new(source_path: "/unter-30", status: "redirect", destination: "/news")
      assert_not chained.valid?, path
    end
  end

  test "does not constantize unsupported polymorphic target classes" do
    rule = LegacyRedirect.new(source_path: "/old", status: "redirect", target_type: "User", target_id: users(:one).id)
    assert_not rule.valid?
    assert_nil rule.destination
  end
end
