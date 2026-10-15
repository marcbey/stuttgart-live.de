require "test_helper"

class LegacyRedirects::MatcherTest < ActiveSupport::TestCase
  setup do
    @event = events(:published_one)
    @event.update!(artist_name: "Christine Thürmer", title: "Wandern total", start_at: Time.zone.local(2027, 11, 10, 20))
  end

  test "matches a title variant only with compatible date and venue" do
    rule = event_rule(artist_name: "Christine Thurmer", production: "Wandern total", date: "2027-11-10", venue: @event.venue)
    assert_equal @event, LegacyRedirects::Matcher.call(rule).target
    rule.source_metadata["date"] = "2027-11-11"
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  test "known different performance times are rejected" do
    rule = event_rule(artist_name: @event.artist_name, production: @event.title, date: "2027-11-10", venue: @event.venue,
      start_at: Time.zone.local(2027, 11, 10, 18).iso8601, time_known: true)
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  test "combined legacy heading matches separate artist and production with date and venue evidence" do
    heading = "#{@event.artist_name} – #{@event.title}"
    rule = event_rule(artist_name: heading, title: heading, date: "2027-11-10", venue: @event.venue,
      start_at: @event.start_at.iso8601, time_known: true)
    result = LegacyRedirects::Matcher.call(rule)
    assert_equal @event, result&.target
    assert_equal "event_identity", result&.reason

    rule.source_metadata["start_at"] = (@event.start_at + 1.hour).iso8601
    assert_nil LegacyRedirects::Matcher.call(rule)
    rule.source_metadata["start_at"] = @event.start_at.iso8601
    rule.source_metadata["venue"] = "Ein anderer Veranstaltungsort"
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  test "combined headings do not erase conflicting numbered productions" do
    [ [ "Ausgabe 12", "Ausgabe 13" ], [ "Ausgabe XII", "Ausgabe XIII" ], [ "Tour 2026", "Tour 2027" ] ].each do |old_label, current_label|
      @event.update!(title: "Wandern total #{current_label}")
      heading = "#{@event.artist_name} – Wandern total #{old_label}"
      rule = event_rule(artist_name: heading, title: heading, date: "2027-11-10", venue: @event.venue)
      assert_nil LegacyRedirects::Matcher.call(rule), "Conflicting #{old_label} and #{current_label} must not redirect"
    end
  end

  test "combined heading does not bypass ambiguity or explicit production evidence" do
    heading = "#{@event.artist_name} – #{@event.title}"
    rule = event_rule(artist_name: heading, title: heading, date: "2027-11-10", venue: @event.venue)
    second = @event.dup
    second.assign_attributes(slug: "combined-second-performance", source_fingerprint: "combined-second-performance")
    second.save!
    assert_nil LegacyRedirects::Matcher.call(rule)
    second.destroy!
    rule.source_metadata["production"] = "Ein anderes Programm"
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  test "combined heading cannot substitute for production evidence in a series" do
    series = EventSeries.create!(origin: "manual", name: "Wandern total")
    @event.update!(event_series: series)
    second = @event.dup
    second.assign_attributes(slug: "combined-next-date", source_fingerprint: "combined-next-date", start_at: @event.start_at + 1.day)
    second.save!
    heading = "#{@event.artist_name} – #{@event.title}"
    rule = event_rule(artist_name: heading, title: heading, date: "2027-11-09", venue: @event.venue)
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  test "artist name alone never substitutes for another production" do
    rule = event_rule(artist_name: @event.artist_name, production: "Neue Abenteuer", date: "2027-11-10", venue: @event.venue)
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  test "ambiguous performances do not select an arbitrary winner" do
    @event.dup.tap { |e| e.slug = "second-performance"; e.source_fingerprint = "other-performance"; e.save! }
    rule = event_rule(artist_name: @event.artist_name, production: @event.title, date: "2027-11-10", venue: @event.venue)
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  test "same production may fall back to a real public series lane" do
    series = EventSeries.create!(origin: "manual", name: "Wandern total")
    @event.update!(event_series: series)
    second = @event.dup
    second.assign_attributes(slug: "second-series-date", source_fingerprint: "series-date", start_at: @event.start_at + 1.day)
    second.save!
    rule = event_rule(artist_name: @event.artist_name, production: @event.title, date: "2027-10-01", venue: @event.venue)
    result = LegacyRedirects::Matcher.call(rule)
    assert_equal @event, result.target
    assert_equal "event_series", result.reason
  end

  test "similar news need compatible article content" do
    post = BlogPost.create!(title: "Neues Festival in Stuttgart", teaser: "Musik und Kultur im Sommer", body: "<p>Das neue Festival bringt Musik und Kultur im Sommer nach Stuttgart.</p>",
      author: users(:one), published_by: users(:one), status: "published", published_at: 1.day.ago)
    rule = LegacyRedirect.new(source_path: "/blog/festival-alt", source_kind: "news", source_metadata: {
      "title" => post.title, "content" => "Das neue Festival bringt Musik und Kultur im Sommer nach Stuttgart."
    })
    assert_equal post, LegacyRedirects::Matcher.call(rule).target
    rule.source_metadata["content"] = "Politik Sport Wirtschaft und Immobilien in Berlin"
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  test "edition years cannot be erased by normalization" do
    assert_not LegacyRedirects::Text.compatible_years?("Festival 2026", "Festival 2027")
    assert_equal 1.0, LegacyRedirects::Text.similarity("Thürmer & Band", "Thurmer und Band")
  end

  test "a provider container with different productions is not a series replacement" do
    series = EventSeries.create!(origin: "manual", name: "Unreliable provider group")
    @event.update!(event_series: series)
    second = @event.dup
    second.assign_attributes(title: "Anderes Programm", slug: "different-production", source_fingerprint: "different-production", start_at: @event.start_at + 1.day)
    second.save!
    rule = event_rule(artist_name: @event.artist_name, production: @event.title, date: "2027-10-01", venue: @event.venue)
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  test "score and ambiguity boundaries are enforced" do
    match = ->(record, score) { LegacyRedirects::Matcher::Match.new(record, nil, "test", score) }
    assert_nil LegacyRedirects::Matcher.choose([ match.call(@event, 0.8999) ])
    assert_equal @event, LegacyRedirects::Matcher.choose([ match.call(@event, 0.9) ]).target
    assert_nil LegacyRedirects::Matcher.choose([ match.call(@event, 0.95), match.call(events(:published_past_one), 0.86) ])
    assert_equal @event, LegacyRedirects::Matcher.choose([ match.call(@event, 0.95), match.call(events(:published_past_one), 0.85) ]).target
  end

  test "different numbered editions are never treated as equivalent articles" do
    post = BlogPost.create!(title: "Stuttgarter Kulturfestival", teaser: "Musik Theater und Literatur", body: "<p>Ausgabe 13 des Stuttgarter Kulturfestivals bringt Musik Theater Literatur.</p>",
      author: users(:one), published_by: users(:one), status: "published", published_at: 1.day.ago)
    rule = LegacyRedirect.new(source_path: "/blog/kulturfestival-alt", source_kind: "news", source_metadata: {
      "title" => post.title, "content" => "Ausgabe 12 des Stuttgarter Kulturfestivals bringt Musik Theater Literatur."
    })
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  test "an extracted artist heading without production proof cannot match a series" do
    series = EventSeries.create!(origin: "manual", name: "Christine Thürmer")
    @event.update!(event_series: series, title: @event.artist_name)
    second = @event.dup
    second.assign_attributes(slug: "artist-only-series", source_fingerprint: "artist-only-series", start_at: @event.start_at + 1.day)
    second.save!
    rule = event_rule(artist_name: @event.artist_name, title: @event.artist_name, date: "2027-10-01", venue: @event.venue)
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  test "candidate overflow cannot hide an equally plausible older article" do
    21.times do |index|
      content = index.in?([ 0, 20 ]) ? "Das Kulturfestival bringt Musik Theater Literatur nach Stuttgart." : "Unabhängiger Bericht über Wirtschaft Immobilien Politik in Berlin."
      BlogPost.create!(title: "Festival im Stadtpark", teaser: "Festival im Stadtpark Teaser", body: "<p>#{content}</p>",
        author: users(:one), published_by: users(:one), status: "published", published_at: (index + 1).minutes.ago)
    end
    rule = LegacyRedirect.new(source_path: "/blog/ambiguous-overflow", source_kind: "news", source_metadata: {
      "title" => "Festival im Stadtpark", "content" => "Das Kulturfestival bringt Musik Theater Literatur nach Stuttgart."
    })
    assert_nil LegacyRedirects::Matcher.call(rule)
  end

  private
    def event_rule(**metadata)
      LegacyRedirect.new(source_path: "/events/alt", source_kind: "event", source_metadata: metadata.stringify_keys)
    end
end
