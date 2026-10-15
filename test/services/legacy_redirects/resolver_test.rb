require "test_helper"

class LegacyRedirects::ResolverTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    @event = events(:published_one)
  end

  test "exact provider identity is persisted and reused without matching" do
    rule = LegacyRedirect.create!(source_path: "/events/alter-name", source_kind: "event", source_metadata: {
      "provider_ids" => [ { "source" => "easyticket", "id" => "legacy-provider-1" } ]
    })
    @event.event_offers.create!(source: "easyticket", source_event_id: "legacy-provider-1", priority_rank: 0)
    with_method(Rails, :cache, @cache) do
      result = LegacyRedirects::Resolver.call(path: rule.source_path, query: "utm_source=test")
      assert_equal :redirect, result.status
      assert_equal "/events/#{@event.slug}", result.destination
      assert_equal @event, rule.reload.target
      with_method(LegacyRedirects::Matcher, :call, ->(*) { flunk "stored redirects must not match again" }) do
        assert_equal result.destination, LegacyRedirects::Resolver.call(path: rule.source_path, query: "").destination
      end
    end
  end

  test "manual blocks and targets survive automatic requests" do
    rule = LegacyRedirect.create!(source_path: "/events/blocked", status: "disabled", origin: "manual")
    assert_equal :disabled, LegacyRedirects::Resolver.call(path: rule.source_path, query: "").status
    assert_equal "disabled", rule.reload.status
  end

  test "unpublished targets never redirect even with a stored positive result" do
    rule = LegacyRedirect.create!(source_path: "/events/hidden", status: "redirect", origin: "manual", target: @event)
    @event.update!(status: "needs_review", published_at: nil)
    assert_equal :not_found, LegacyRedirects::Resolver.call(path: rule.source_path, query: "").status
  end

  test "negative cache expires and publication invalidates it immediately" do
    rule = LegacyRedirect.create!(source_path: "/events/negative", source_kind: "event", source_metadata: {
      "provider_ids" => [ { "source" => "easyticket", "id" => "late-1" } ]
    })
    with_method(Rails, :cache, @cache) do
      assert_equal :not_found, LegacyRedirects::Resolver.call(path: rule.source_path, query: "").status
      @event.event_offers.create!(source: "easyticket", source_event_id: "late-1", priority_rank: 0)
      assert_equal :redirect, LegacyRedirects::Resolver.call(path: rule.source_path, query: "").status
    end
  end

  test "unknown scanner paths are not persisted" do
    with_method(Rails, :cache, @cache) do
      assert_no_difference "LegacyRedirect.count" do
        assert_equal :not_found, LegacyRedirects::Resolver.call(path: "/missing-probe", query: "").status
      end
    end
  end

  test "technical matching errors do not save a negative outcome" do
    rule = LegacyRedirect.create!(source_path: "/events/technical", source_kind: "event")
    with_method(LegacyRedirects::Matcher, :call, ->(*) { raise IOError, "broken" }) do
      assert_raises(IOError) { LegacyRedirects::Resolver.call(path: rule.source_path, query: "") }
    end
    assert_nil rule.reload.checked_at
  end

  test "imported blog source URL resolves without a prior inventory row" do
    post = BlogPost.create!(title: "Quellartikel", teaser: "Quellartikel Vorschau", body: "<p>Quellartikel Inhalt</p>",
      author: users(:one), published_by: users(:one), status: "published", published_at: 1.day.ago,
      source_url: "https://stuttgart-live.de/blog/quellartikel/")
    result = LegacyRedirects::Resolver.call(path: "/blog/quellartikel", query: "")
    assert_equal "/news/#{post.slug}", result.destination
    assert_equal post, LegacyRedirect.find_by!(source_path: "/blog/quellartikel").target
  end


  test "a concurrent manual decision wins over a negative matching result" do
    rule = LegacyRedirect.create!(source_path: "/events/concurrent-block", source_kind: "event")
    with_method(LegacyRedirects::Matcher, :call, ->(_) { rule.update!(origin: "manual", status: "disabled"); nil }) do
      assert_equal :disabled, LegacyRedirects::Resolver.call(path: rule.source_path, query: "").status
    end
    assert_equal "disabled", rule.reload.status
  end

  test "invalid automatic targets are re-resolved to another equivalent public target" do
    other = events(:published_past_one)
    [ @event, other ].each do |event|
      event.event_offers.create!(source: "easyticket", source_event_id: "changed-target", priority_rank: 0)
    end
    rule = LegacyRedirect.create!(source_path: "/events/changed-target", source_kind: "event", status: "redirect", target: @event,
      source_metadata: { "provider_ids" => [ { "source" => "easyticket", "id" => "changed-target" } ] })
    @event.update!(status: "needs_review", published_at: nil)
    assert_equal "/events/#{other.slug}", LegacyRedirects::Resolver.call(path: rule.source_path, query: "").destination
    assert_equal other, rule.reload.target
  end

  test "negative outcomes expire after fifteen minutes" do
    rule = LegacyRedirect.create!(source_path: "/events/expiry", source_kind: "event")
    with_method(Rails, :cache, @cache) do
      LegacyRedirects::Resolver.call(path: rule.source_path, query: "")
      calls = 0
      with_method(LegacyRedirects::Matcher, :call, ->(_) { calls += 1; nil }) do
        LegacyRedirects::Resolver.call(path: rule.source_path, query: "")
        assert_equal 0, calls
        travel 16.minutes do
          LegacyRedirects::Resolver.call(path: rule.source_path, query: "")
        end
        assert_equal 1, calls
      end
    end
  end

  test "a concurrent inserted manual mapping wins without uniqueness errors" do
    path = "/events/concurrent-insert"
    match = LegacyRedirects::Matcher::Match.new(@event, nil, "test", 1.0)
    with_method(LegacyRedirects::Matcher, :call, ->(_) {
      LegacyRedirect.create!(source_path: path, source_kind: "event", origin: "manual", status: "redirect", target_path: "/news")
      match
    }) do
      result = LegacyRedirects::Resolver.call(path: path, query: "")
      assert_equal "/news", result.destination
      assert_equal 1, LegacyRedirect.where(source_path: path).count
    end
  end

  test "new inventory evidence bypasses an earlier unknown-path negative cache" do
    @event.event_offers.create!(source: "easyticket", source_event_id: "inventory-evidence", priority_rank: 0)
    with_method(Rails, :cache, @cache) do
      assert_equal :not_found, LegacyRedirects::Resolver.call(path: "/events/new-evidence", query: "").status
      LegacyRedirect.create!(source_path: "/events/new-evidence", source_kind: "event",
        source_metadata: { "provider_ids" => [ { "source" => "easyticket", "id" => "inventory-evidence" } ] })
      assert_equal :redirect, LegacyRedirects::Resolver.call(path: "/events/new-evidence", query: "").status
    end
  end

  test "refreshed evidence rechecks even a still-public automatic target" do
    other = events(:published_past_one)
    other.event_offers.create!(source: "easyticket", source_event_id: "refreshed-evidence", priority_rank: 0)
    rule = LegacyRedirect.create!(source_path: "/events/refreshed-evidence", source_kind: "event", status: "redirect", target: @event,
      source_metadata: { "provider_ids" => [ { "source" => "easyticket", "id" => "refreshed-evidence" } ] })
    assert_nil rule.checked_at
    assert_equal "/events/#{other.slug}", LegacyRedirects::Resolver.call(path: rule.source_path, query: "").destination
  end

  test "scheduled blog publication expires earlier negative cache at its publication time" do
    with_method(Rails, :cache, @cache) do
      release = 2.minutes.from_now.change(usec: 0)
      post = BlogPost.create!(title: "Geplante Nachricht", teaser: "Geplante Nachricht Teaser", body: "<p>Geplante Nachricht Inhalt</p>",
        author: users(:one), published_by: users(:one), status: "published", published_at: release,
        source_url: "https://stuttgart-live.de/blog/geplante-nachricht/")
      assert_equal :not_found, LegacyRedirects::Resolver.call(path: "/blog/geplante-nachricht", query: "").status
      travel_to release + 1.second do
        assert_equal "/news/#{post.slug}", LegacyRedirects::Resolver.call(path: "/blog/geplante-nachricht", query: "").destination
      end
    end
  end

  test "scheduled event publication expires a persisted negative result without a write" do
    with_method(Rails, :cache, @cache) do
      release = 2.minutes.from_now.change(usec: 0)
      @event.update_columns(status: "published", published_at: release)
      @event.event_offers.create!(source: "easyticket", source_event_id: "scheduled-event", priority_rank: 0)
      rule = LegacyRedirect.create!(source_path: "/events/scheduled-event", source_kind: "event",
        source_metadata: { "provider_ids" => [ { "source" => "easyticket", "id" => "scheduled-event" } ] })
      assert_equal :not_found, LegacyRedirects::Resolver.call(path: rule.source_path, query: "").status
      travel_to release + 1.second do
        assert_equal :redirect, LegacyRedirects::Resolver.call(path: rule.source_path, query: "").status
      end
    end
  end

  test "a source refresh during matching cannot persist a result from obsolete evidence" do
    rule = LegacyRedirect.create!(source_path: "/events/concurrent-source-refresh", source_kind: "event", source_metadata: { "title" => "Old evidence" })
    stale_match = LegacyRedirects::Matcher::Match.new(@event, nil, "test", 1.0)
    with_method(LegacyRedirects::Matcher, :call, ->(_) {
      rule.update!(source_metadata: { "title" => "Changed evidence" }, checked_at: nil)
      stale_match
    }) do
      result = LegacyRedirects::Resolver.call(path: rule.source_path, query: "")
      assert_equal :not_found, result.status
      assert_equal "unresolved", rule.reload.status
      assert_nil rule.checked_at
      assert_nil rule.target
    end
  end

  test "a negative match cannot cache newly refreshed source evidence as missing" do
    rule = LegacyRedirect.create!(source_path: "/events/concurrent-negative-refresh", source_kind: "event", source_metadata: { "title" => "Old evidence" })
    with_method(LegacyRedirects::Matcher, :call, ->(_) {
      rule.update!(source_metadata: { "title" => "Changed evidence" }, checked_at: nil)
      nil
    }) do
      assert_equal :not_found, LegacyRedirects::Resolver.call(path: rule.source_path, query: "").status
      assert_nil rule.reload.checked_at
    end
  end

  private
    def with_method(object, name, replacement)
      original = object.method(name)
      object.define_singleton_method(name, replacement.respond_to?(:call) ? replacement : -> { replacement })
      yield
    ensure
      object.define_singleton_method(name, original) if original
    end
end
