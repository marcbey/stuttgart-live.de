require "test_helper"

class Events::Retention::PruneStaleUnpublishedEventsTest < ActiveSupport::TestCase
  setup do
    @now = Time.zone.parse("2026-04-15 10:00:00")
  end

  test "deletes non-published stale events and their dependent records" do
    stale_event = Event.create!(
      slug: "stale-retention-needs-review",
      source_fingerprint: "test::retention::stale-needs-review",
      title: "Stale Retention Event",
      artist_name: "Stale Artist",
      normalized_artist_name: "staleartist",
      start_at: Time.zone.parse("2026-03-10 20:00:00"),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review",
      source_snapshot: {}
    )
    stale_event.event_offers.create!(
      source: "eventim",
      source_event_id: "offer-1",
      ticket_url: "https://example.com/tickets/offer-1",
      ticket_price_text: "19,00 EUR"
    )
    stale_event.event_change_logs.create!(
      action: "updated",
      changed_fields: { "status" => [ "imported", "needs_review" ] },
      metadata: {}
    )
    stale_image = stale_event.event_images.build(purpose: "detail_hero")
    stale_image.file.attach(create_uploaded_blob(filename: "stale-retention.png"))
    stale_image.save!
    stale_event.import_event_images.create!(
      source: "eventim",
      image_type: "large",
      image_url: "https://example.com/stale-retention.jpg",
      role: "cover",
      aspect_hint: "landscape",
      position: 0
    )
    EventLlmEnrichment.create!(
      event: stale_event,
      source_run: import_runs(:one),
      genre: [ "Rock" ],
      venue: stale_event.venue,
      event_description: "Event-Beschreibung",
      venue_description: "Venue-Beschreibung",
      model: "gpt-5-mini",
      prompt_version: "v1",
      raw_response: {}
    )

    future_unpublished_event = Event.create!(
      slug: "future-retention-imported",
      source_fingerprint: "test::retention::future-imported",
      title: "Future Imported Event",
      artist_name: "Future Artist",
      normalized_artist_name: "futureartist",
      start_at: Time.zone.parse("2026-05-20 20:00:00"),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "imported",
      source_snapshot: {}
    )
    stale_published_event = Event.create!(
      slug: "stale-retention-published",
      source_fingerprint: "test::retention::stale-published",
      title: "Stale Published Event",
      artist_name: "Published Artist",
      normalized_artist_name: "publishedartistretention",
      start_at: Time.zone.parse("2026-03-10 20:00:00"),
      venue: "LKA Longhorn",
      city: "Stuttgart",
      status: "published",
      published_at: Time.zone.parse("2026-02-20 12:00:00"),
      source_snapshot: {}
    )

    result = travel_to(@now) { Events::Retention::PruneStaleUnpublishedEvents.call(scope: Event.where(id: [ stale_event.id, future_unpublished_event.id, stale_published_event.id ])) }

    assert_not Event.exists?(stale_event.id)
    assert Event.exists?(future_unpublished_event.id)
    assert Event.exists?(stale_published_event.id)
    assert_equal 0, EventOffer.where(event_id: stale_event.id).count
    assert_equal 0, EventChangeLog.where(event_id: stale_event.id).count
    assert_equal 0, EventImage.where(event_id: stale_event.id).count
    assert_equal 0, EventLlmEnrichment.where(event_id: stale_event.id).count
    assert_equal 0, ImportEventImage.where(import_class: "Event", import_event_id: stale_event.id).count
    assert_equal 1, result.deleted_count
    assert_equal({ "needs_review" => 1 }, result.deleted_by_status)
    assert_equal Time.zone.parse("2026-03-15 00:00:00"), result.cutoff_at
  end

  test "deletes stale events across all non-published statuses" do
    stale_statuses = %w[imported needs_review ready_for_publish rejected]

    stale_statuses.each do |status|
      Event.create!(
        slug: "stale-retention-#{status}",
        source_fingerprint: "test::retention::#{status}",
        title: "Stale #{status}",
        artist_name: "Artist #{status}",
        normalized_artist_name: "artist#{status}",
        start_at: Time.zone.parse("2026-03-01 20:00:00"),
        venue: "Im Wizemann",
        city: "Stuttgart",
        status: status,
        source_snapshot: {}
      )
    end

    result = travel_to(@now) do
      Events::Retention::PruneStaleUnpublishedEvents.call(
        scope: Event.where(source_fingerprint: stale_statuses.map { |status| "test::retention::#{status}" })
      )
    end

    assert_equal 4, result.deleted_count
    assert_equal(
      {
        "imported" => 1,
        "needs_review" => 1,
        "ready_for_publish" => 1,
        "rejected" => 1
      },
      result.deleted_by_status
    )
  end
end
