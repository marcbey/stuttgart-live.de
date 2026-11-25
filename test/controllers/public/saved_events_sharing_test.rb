require "test_helper"

class Public::SavedEventsSharingTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    @event = events(:published_one)
    @second_event = @event.dup
    @second_event.assign_attributes(slug: "second-shared-event", source_fingerprint: "test::second-shared-event",
                                    artist_name: "Second Artist", start_at: Time.zone.local(2026, 6, 2, 20))
    @second_event.save!
  end

  teardown { travel_back }

  test "clear list controls are present in the heart menu overview and homepage lane" do
    get root_path

    assert_response :success
    assert_select ".design-preview-saved-panel-footer button[data-controller='saved-events-clear']", text: "Merkliste leeren"

    get saved_events_path

    assert_response :success
    assert_select ".design-preview-saved-panel-footer button[data-controller='saved-events-clear']", text: "Merkliste leeren"
    assert_select ".saved-events-page-toolbar button[data-controller='saved-events-clear']", text: "Merkliste leeren"

    get saved_lane_events_path, params: { slugs: [ @event.slug ] }

    assert_response :success
    assert_select ".lane-header--saved-events button[data-controller='saved-events-clear']", text: "Merkliste leeren"
  end

  test "shared list exposes its selected events and image without javascript" do
    slugs = [ @second_event.slug, @event.slug ]
    get saved_events_path, params: { slugs: slugs }

    assert_response :success
    assert_select "meta[property='og:title'][content=?]", "2 Events für dich | STUTTGART LIVE"
    assert_select "meta[property='og:description']" do |tags|
      description = tags.first["content"]
      assert_includes description, "Published Artist · 01.06.2026"
      assert_includes description, "Second Artist · 02.06.2026"
    end
    assert_select "meta[property='og:image'][content='https://example.com/published.jpg']"
    assert_select "meta[name='twitter:card'][content='summary_large_image']"
    assert_select "meta[property='og:url'][content=?]", saved_events_url(slugs: slugs)
    assert_select "meta[name='robots'][content='noindex, follow']"
  end

  test "preview excludes unpublished scheduled and past events even for signed in editors" do
    sign_in_as(users(:one))
    @second_event.update!(published_at: 1.day.from_now)
    get saved_events_path, params: { slugs: [ @event.slug, @event.slug, @second_event.slug,
                                            events(:needs_review_one).slug, events(:published_past_one).slug, "missing" ] }

    assert_response :success
    assert_select "meta[property='og:title'][content=?]", "1 Event für dich | STUTTGART LIVE"
    assert_select "meta[property='og:description']" do |tags|
      assert_includes tags.first["content"], "Published Artist"
      assert_no_match(/Second Artist|Review Artist|Past Artist|missing/, tags.first["content"])
    end
  end

  test "image is taken from the next selected event when the first has no photo" do
    @second_event.update!(start_at: 1.day.from_now)
    get saved_events_path, params: { slugs: [ @second_event.slug, @event.slug ] }

    assert_select "meta[property='og:image'][content='https://example.com/published.jpg']"
  end

  test "a selection without photos uses the large brand heart as an absolute image url" do
    get saved_events_path, params: { slugs: [ @second_event.slug ] }

    assert_response :success
    assert_select "meta[property='og:image'][content='http://www.example.com/icon.png']"
  end

  test "missing selections have a neutral preview without unrelated event details" do
    get saved_events_path, params: { slugs: [ "unknown" ] }

    assert_response :success
    assert_select "meta[property='og:title'][content=?]", "Meine Eventauswahl | STUTTGART LIVE"
    assert_select "meta[property='og:description'][content=?]", "Entdecke die geteilte Eventauswahl bei STUTTGART LIVE."
  end

  test "dropdown supplies escaped share text with the selected event date and venue" do
    @event.update!(artist_name: 'Act & "Friends" <Live>')
    get saved_lane_events_path, params: { slugs: [ @event.slug ], mode: "dropdown" }

    assert_response :success
    assert_select "li[data-slug=?]", @event.slug do |items|
      assert_equal "Act & \"Friends\" <Live>\nDatum: 01.06.2026\nOrt: LKA Longhorn", items.first["data-share-text"]
    end
  end

  test "comma separated shared urls describe the same selection as the javascript list" do
    get saved_events_path, params: { slugs: [ "#{@event.slug},#{@second_event.slug}", @event.slug ] }

    assert_select "meta[property='og:title'][content=?]", "2 Events für dich | STUTTGART LIVE"
    assert_select "meta[property='og:url'][content=?]", saved_events_url(slugs: [ @event.slug, @second_event.slug ])
  end

  test "long selections keep three event names dates and the remainder within the preview limit" do
    @event.update!(artist_name: "First artist with an exceptionally long name")
    @second_event.update!(artist_name: "Second artist with an exceptionally long name")
    third_event = @second_event.dup
    third_event.assign_attributes(slug: "third-shared-event", source_fingerprint: "test::third-shared-event",
                                 artist_name: "Third artist with an exceptionally long name", start_at: Time.zone.local(2026, 6, 3, 20))
    third_event.save!
    fourth_event = third_event.dup
    fourth_event.assign_attributes(slug: "fourth-shared-event", source_fingerprint: "test::fourth-shared-event",
                                  artist_name: "Fourth Artist", start_at: Time.zone.local(2026, 6, 4, 20))
    fourth_event.save!

    get saved_events_path, params: { slugs: [ @event.slug, @second_event.slug, third_event.slug, fourth_event.slug ] }

    assert_select "meta[property='og:description']" do |tags|
      description = tags.first["content"]
      assert_operator description.length, :<=, 160
      %w[First Second Third 01.06.2026 02.06.2026 03.06.2026].each { |text| assert_includes description, text }
      assert_match(/und 1 weiteres Event\.\z/, description)
    end
  end
end
