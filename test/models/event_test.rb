require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    @fixture_path = Rails.root.join("test/fixtures/files/test_image.png")
  end

  test "splits combined title into artist and tour when artist still equals title" do
    event = Event.new(
      artist_name: "WILHELMINE - magisch Tour 2026",
      title: "WILHELMINE - magisch Tour 2026",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal "WILHELMINE", event.artist_name
    assert_equal "magisch Tour 2026", event.title
  end

  test "removes artist prefix from title when artist is already set separately" do
    event = Event.new(
      artist_name: "WILHELMINE",
      title: "WILHELMINE - magisch Tour 2026",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal "WILHELMINE", event.artist_name
    assert_equal "magisch Tour 2026", event.title
  end

  test "keeps title unchanged when it does not start with the artist name" do
    event = Event.new(
      artist_name: "WILHELMINE",
      title: "Special Guest Night - magisch Tour 2026",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal "WILHELMINE", event.artist_name
    assert_equal "Special Guest Night - magisch Tour 2026", event.title
  end

  test "normalizes kulturquartier venue name without proton" do
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Kulturquartier - PROTON",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal "Kulturquartier (Proton)", event.venue
  end

  test "reuses an existing venue by name" do
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue_name: " im wizemann ",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venues(:im_wizemann), event.venue_record
  end

  test "reuses an existing venue by flexible match name" do
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 11, 20, 0, 0),
      venue_name: "LKA-Longhorn Stuttgart",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venues(:lka_longhorn), event.venue_record
  end

  test "reuses an existing venue despite apostrophe variant and stuttgart suffix" do
    venue = Venue.create!(name: "Goldmark's")
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 11, 20, 0, 0),
      venue_name: "Goldmark´s Stuttgart",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venue, event.venue_record
  end

  test "reuses the official schleyer halle venue for shorthand aliases" do
    venue = Venue.create!(name: "Hanns-Martin-Schleyer-Halle")
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 11, 20, 0, 0),
      venue_name: "Schleyer-Halle Stuttgart",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venue, event.venue_record
    assert_equal "Hanns-Martin-Schleyer-Halle", event.venue
  end

  test "reuses the canonical hospitalhof venue for hall-specific aliases" do
    venue = Venue.create!(name: "Hospitalhof")
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 12, 20, 0, 0),
      venue_name: "Hospitalhof, Paul-Lechler-Saal",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venue, event.venue_record
    assert_equal "Hospitalhof", event.venue
  end

  test "reuses the canonical kulinarium venue for romerhof alias" do
    venue = Venue.create!(name: "Kulinarium an der Glems")
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 15, 20, 0, 0),
      venue_name: "Kulinarium an der Glems/Römerhof",
      city: "Leonberg",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venue, event.venue_record
    assert_equal "Kulinarium an der Glems", event.venue
  end

  test "reuses the canonical kulturquartier proton venue for club aliases" do
    venue = Venue.create!(name: "Kulturquartier (Proton)")
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 16, 20, 0, 0),
      venue_name: "Kulturquartier Stuttgart ( the Club)",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venue, event.venue_record
    assert_equal "Kulturquartier (Proton)", event.venue
  end

  test "reuses the canonical schraglage venue for club aliases" do
    venue = Venue.create!(name: "Schräglage")
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 17, 20, 0, 0),
      venue_name: "Schräglage Club",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venue, event.venue_record
    assert_equal "Schräglage", event.venue
  end

  test "reuses the canonical fitz venue for fitz aliases" do
    venue = Venue.create!(name: "FITZ! Figurentheater")
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 18, 20, 0, 0),
      venue_name: "FITZ Das Theater animierter Formen",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venue, event.venue_record
    assert_equal "FITZ! Figurentheater", event.venue
  end

  test "reuses the canonical das k venue for room aliases" do
    venue = Venue.create!(name: "Das K-Kultur-und Kongresszentrum")
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 19, 20, 0, 0),
      venue_name: "Das K - Kultur- und Kongresszentrum - Festsaal",
      city: "Kornwestheim",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venue, event.venue_record
    assert_equal "Das K-Kultur-und Kongresszentrum", event.venue
  end

  test "reuses the canonical scala ludwigsburg venue for scala theater aliases" do
    venue = Venue.create!(name: "Scala Ludwigsburg")
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 14, 20, 0, 0),
      venue_name: "Scala Theater Ludwigsburg",
      city: "Ludwigsburg",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venue, event.venue_record
    assert_equal "Scala Ludwigsburg", event.venue
  end

  test "reuses canonical liederhalle hall venues for hall aliases" do
    venue = Venue.create!(name: "Kultur- und Kongresszentrum Liederhalle Hegel-Saal")
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 13, 20, 0, 0),
      venue_name: "Liederhalle Stuttgart - Hegelsaal",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal venue, event.venue_record
    assert_equal "Kultur- und Kongresszentrum Liederhalle Hegel-Saal", event.venue
  end

  test "creates a new venue from venue_name on save" do
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue_name: "Neue Test Venue",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert_difference -> { Venue.count }, 1 do
      event.save!
    end

    assert_equal "Neue Test Venue", event.reload.venue
    assert_equal "Neue Test Venue", event.venue_record.name
  end

  test "allows blank city and normalizes it to nil" do
    event = Event.new(
      artist_name: "Test Artist",
      title: "Test Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "   ",
      status: "needs_review"
    )

    assert event.valid?
    assert_nil event.city
  end

  test "sets normalized_artist_name from artist_name" do
    event = Event.new(
      artist_name: "Band X + Support",
      title: "Band X - Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )

    assert event.valid?
    assert_equal "bandx", event.normalized_artist_name
  end

  test "normal save downgrades published events with a future publication date to ready_for_publish" do
    event = events(:published_one)
    scheduled_time = 2.days.from_now.change(usec: 0)

    event.update!(published_at: scheduled_time)

    assert_equal "ready_for_publish", event.reload.status
    assert_equal scheduled_time, event.published_at
  end

  test "normal save keeps needs_review events with a future publication date in needs_review" do
    event = events(:needs_review_one)
    scheduled_time = 2.days.from_now.change(usec: 0)

    event.update!(published_at: scheduled_time)

    assert_equal "needs_review", event.reload.status
    assert_equal scheduled_time, event.published_at
  end

  test "normal save publishes ready_for_publish events when the publication date is due" do
    event = events(:needs_review_one)
    event.update!(status: "ready_for_publish")

    due_time = 2.hours.ago.change(usec: 0)
    event.update!(published_at: due_time)

    assert_equal "published", event.reload.status
    assert_equal due_time, event.published_at
  end

  test "normal save leaves the status unchanged when no publication date is present" do
    event = events(:needs_review_one)

    event.update!(title: "Updated Without Publication Date")

    assert_equal "needs_review", event.reload.status
    assert_nil event.published_at
  end

  test "syncs publication fields without setting published_at automatically" do
    event = events(:published_one)
    event.published_at = nil
    event.published_by = nil

    event.sync_publication_fields(user: users(:blogger))

    assert_nil event.published_at
    assert_equal users(:blogger), event.published_by
  end

  test "publish_now persists a manual publication state" do
    event = events(:needs_review_one)

    event.publish_now!(user: users(:one), auto_published: false)

    assert_equal "published", event.status
    assert_equal false, event.auto_published
    assert_nil event.published_at
    assert_equal users(:one), event.published_by
  end

  test "publish rejects an explicitly scheduled publication time" do
    event = events(:needs_review_one)
    scheduled_time = 2.days.from_now.change(usec: 0)
    event.published_at = scheduled_time

    error = assert_raises(ActiveRecord::RecordInvalid) do
      event.publish!(user: users(:one), auto_published: false)
    end

    assert_includes error.record.errors.full_messages.to_sentence, "liegt in der Zukunft"
    assert_equal scheduled_time, event.published_at
  end

  test "unpublish clears persisted publication fields" do
    event = events(:published_one)

    event.unpublish!(status: "ready_for_publish", auto_published: false)

    assert_equal "ready_for_publish", event.status
    assert_equal false, event.auto_published
    assert_nil event.published_at
    assert_nil event.published_by
  end

  test "past? is true only after the event start time" do
    freeze_time do
      past_event = Event.new(start_at: 5.minutes.ago)
      future_event = Event.new(start_at: 5.minutes.from_now)

      assert_predicate past_event, :past?
      assert_not_predicate future_event, :past?
    end
  end

  test "scheduled? and live? distinguish future and current publication windows" do
    freeze_time do
      scheduled_event = Event.new(status: "ready_for_publish", published_at: 2.hours.from_now)
      live_event = Event.new(status: "published", published_at: 2.hours.ago)
      immediate_event = Event.new(status: "published", published_at: nil)

      assert_predicate scheduled_event, :scheduled?
      assert_not_predicate scheduled_event, :live?
      assert_not_predicate live_event, :scheduled?
      assert_predicate live_event, :live?
      assert_not_predicate immediate_event, :scheduled?
      assert_predicate immediate_event, :live?
    end
  end

  test "preferred_ticket_offer uses loaded offers without extra queries" do
    event = Event.includes(:event_offers).find(events(:published_one).id)
    expected_offer = event_offers(:published_one_offer)

    queries = capture_sql_queries { assert_equal expected_offer, event.preferred_ticket_offer }

    assert_equal 0, queries
  end

  test "editor_ticket_offer prefers manual offers over imported offers" do
    event = Event.create!(
      slug: "editor-ticket-offer-priority",
      source_fingerprint: "test::event::editor-ticket-offer-priority",
      artist_name: "Editor Artist",
      title: "Editor Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "needs_review"
    )
    manual_offer = event.event_offers.create!(
      source: "manual",
      source_event_id: event.id.to_s,
      ticket_url: "https://manual.example/tickets",
      sold_out: false,
      priority_rank: 0
    )
    imported_offer = event.event_offers.create!(
      source: "eventim",
      source_event_id: "eventim-1",
      ticket_url: "https://eventim.example/tickets",
      sold_out: true,
      priority_rank: 50
    )

    assert_equal manual_offer, event.editor_ticket_offer
    assert_equal manual_offer, event.manual_ticket_offer
  end

  test "public_ticket_offer blocks manual fallback when imported primary offer is unavailable" do
    event = Event.create!(
      slug: "public-ticket-offer-blocks-manual",
      source_fingerprint: "test::event::public-ticket-offer-blocks-manual",
      artist_name: "Public Artist",
      title: "Public Tour",
      start_at: Time.zone.local(2026, 10, 11, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.hour.ago
    )
    imported_offer = event.event_offers.create!(
      source: "easyticket",
      source_event_id: "easy-1",
      ticket_url: "https://easyticket.example/tickets",
      sold_out: true,
      priority_rank: 0
    )
    manual_offer = event.event_offers.create!(
      source: "manual",
      source_event_id: event.id.to_s,
      ticket_url: "https://manual.example/tickets",
      sold_out: false,
      priority_rank: 0
    )

    assert_equal manual_offer, event.editor_ticket_offer
    assert_nil event.public_ticket_offer
    assert_equal manual_offer, event.manual_ticket_offer
  end

  test "public_ticket_offer falls back to manual when no imported offer exists" do
    event = Event.create!(
      slug: "public-ticket-offer-manual-fallback",
      source_fingerprint: "test::event::public-ticket-offer-manual-fallback",
      artist_name: "Manual Artist",
      title: "Manual Tour",
      start_at: Time.zone.local(2026, 10, 12, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.hour.ago
    )
    manual_offer = event.event_offers.create!(
      source: "manual",
      source_event_id: event.id.to_s,
      ticket_url: "https://manual.example/fallback",
      sold_out: false,
      priority_rank: 0
    )

    assert_equal manual_offer, event.editor_ticket_offer
    assert_equal manual_offer, event.public_ticket_offer
  end

  test "public_ticket_status_offer prefers imported offers over manual offers" do
    event = Event.create!(
      slug: "public-ticket-status-offer-priority",
      source_fingerprint: "test::event::public-ticket-status-offer-priority",
      artist_name: "Status Artist",
      title: "Status Tour",
      start_at: Time.zone.local(2026, 10, 13, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.hour.ago
    )
    manual_offer = event.event_offers.create!(
      source: "manual",
      source_event_id: event.id.to_s,
      ticket_url: "https://manual.example/status",
      sold_out: false,
      priority_rank: 0
    )
    imported_offer = event.event_offers.create!(
      source: "easyticket",
      source_event_id: "easy-status-1",
      ticket_url: "https://easyticket.example/status",
      sold_out: true,
      priority_rank: 10
    )

    assert_equal imported_offer, event.public_ticket_status_offer
    assert_not_equal manual_offer, event.public_ticket_status_offer
  end

  test "public_sold_out? follows the leading public ticket status offer" do
    event = Event.create!(
      slug: "public-sold-out-leading-offer",
      source_fingerprint: "test::event::public-sold-out-leading-offer",
      artist_name: "Sold Out Artist",
      title: "Sold Out Tour",
      start_at: Time.zone.local(2026, 10, 14, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.hour.ago
    )
    event.event_offers.create!(
      source: "easyticket",
      source_event_id: "easy-sold-out-1",
      ticket_url: "https://easyticket.example/sold-out",
      sold_out: true,
      priority_rank: 0
    )
    event.event_offers.create!(
      source: "manual",
      source_event_id: event.id.to_s,
      ticket_url: "https://manual.example/available",
      sold_out: false,
      priority_rank: 0
    )

    assert_predicate event, :public_sold_out?
    assert_nil event.public_ticket_offer
  end

  test "public_canceled? takes precedence over sold out when the leading offer is canceled" do
    event = Event.create!(
      slug: "public-canceled-leading-offer",
      source_fingerprint: "test::event::public-canceled-leading-offer",
      artist_name: "Canceled Artist",
      title: "Canceled Tour",
      start_at: Time.zone.local(2026, 10, 15, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.hour.ago
    )
    event.event_offers.create!(
      source: "eventim",
      source_event_id: "eventim-canceled-1",
      ticket_url: "https://eventim.example/canceled",
      sold_out: true,
      priority_rank: 0,
      metadata: {
        "availability_status" => "canceled",
        "source_status_code" => "1"
      }
    )
    event.event_offers.create!(
      source: "manual",
      source_event_id: event.id.to_s,
      ticket_url: "https://manual.example/available",
      sold_out: false,
      priority_rank: 0
    )

    assert_predicate event, :public_canceled?
    assert_not event.public_sold_out?
    assert_nil event.public_ticket_offer
    assert_equal "Abgesagt", event.public_ticket_status_label
  end

  test "primary_genre uses loaded genres without extra queries" do
    event = Event.includes(:genres).find(events(:published_one).id)
    expected_genre = genres(:rock)

    queries = capture_sql_queries { assert_equal expected_genre, event.primary_genre }

    assert_equal 0, queries
  end

  test "image_for uses loaded import images without extra queries" do
    event = Event.includes(:event_images, :import_event_images).find(events(:published_one).id)
    expected_image = import_event_images(:published_cover)

    queries = capture_sql_queries do
      assert_equal expected_image, event.image_for(slot: :grid_default, breakpoint: :mobile)
    end

    assert_equal 0, queries
  end

  test "image_for uses loaded event images without extra queries" do
    event = events(:published_one)
    event_image = create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO)
    loaded_event = Event.includes(:event_images, :import_event_images).find(event.id)

    queries = capture_sql_queries do
      assert_equal event_image, loaded_event.image_for(slot: :detail_hero, breakpoint: :desktop)
    end

    assert_equal 0, queries
  end

  test "image_url_for returns optimized representation path for editorial images" do
    event = events(:published_one)
    event_image = create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO)

    assert_equal(
      Rails.application.routes.url_helpers.rails_storage_proxy_path(event_image.processed_optimized_variant, only_path: true),
      event.image_url_for(slot: :detail_hero, breakpoint: :desktop)
    )
  end

  test "promotion banner does not require detail hero image" do
    event = Event.new(
      artist_name: "Promo Artist",
      title: "Promo Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.hour.ago,
      promotion_banner: true
    )

    assert event.valid?
  end

  test "pending promotion banner blob satisfies image validation" do
    event = Event.new(
      artist_name: "Promo Artist",
      title: "Promo Tour",
      start_at: Time.zone.local(2026, 10, 10, 20, 0, 0),
      venue: "Im Wizemann",
      city: "Stuttgart",
      status: "published",
      published_at: 1.hour.ago,
      promotion_banner: true
    )
    event.pending_promotion_banner_image_blob = create_uploaded_blob(filename: "pending-event-banner.png")

    assert_predicate event, :valid?
  end

  test "promotion banner image crop values fall back to defaults" do
    event = events(:published_one)

    assert_equal Event::DEFAULT_IMAGE_FOCUS_X, event.promotion_banner_image_focus_x_value
    assert_equal Event::DEFAULT_IMAGE_FOCUS_Y, event.promotion_banner_image_focus_y_value
    assert_equal Event::DEFAULT_IMAGE_ZOOM, event.promotion_banner_image_zoom_value
  end

  test "promotion banner clears previous banner event" do
    first = events(:published_one)
    second = Event.create!(
      slug: "second-promotion-banner-event",
      source_fingerprint: "test::event::second-promotion-banner",
      title: "Zweiter Promotion Banner",
      artist_name: "Zweiter Banner Artist",
      start_at: 12.days.from_now.change(hour: 20, min: 0, sec: 0),
      venue: "Liederhalle",
      city: "Stuttgart",
      status: "published",
      published_at: 1.day.ago,
      source_snapshot: {}
    )
    create_event_image(event: first, purpose: EventImage::PURPOSE_DETAIL_HERO)
    create_event_image(event: second, purpose: EventImage::PURPOSE_DETAIL_HERO)

    first.update!(promotion_banner: true)
    second.update!(promotion_banner: true)

    assert_predicate second.reload, :promotion_banner?
    assert_not first.reload.promotion_banner?
  end

  test "promotion banner texts fall back to defaults" do
    event = events(:published_one)

    assert_equal "Promotion", event.promotion_banner_kicker_text_value
    assert_equal "Zum Event", event.promotion_banner_cta_text_value
    assert_equal "#E0F7F2", event.promotion_banner_background_color_value
    assert_equal "dark", event.promotion_banner_text_color_scheme
  end

  test "promotion banner texts are normalized" do
    event = events(:published_one)
    create_event_image(event: event, purpose: EventImage::PURPOSE_DETAIL_HERO)

    event.update!(
      promotion_banner: true,
      promotion_banner_kicker_text: "  Szene Tipp  ",
      promotion_banner_cta_text: "  Jetzt ansehen  "
    )

    assert_equal "Szene Tipp", event.promotion_banner_kicker_text
    assert_equal "Jetzt ansehen", event.promotion_banner_cta_text
  end

  test "promotion banner background color is normalized" do
    event = events(:published_one)

    event.update!(promotion_banner_background_color: "  18333a ")

    assert_equal "#18333A", event.promotion_banner_background_color
    assert_equal "#18333A", event.promotion_banner_background_color_value
  end

  test "promotion banner background color rejects invalid values" do
    event = events(:published_one)

    event.promotion_banner_background_color = "#ABC"

    assert_not event.valid?
    assert_includes event.errors[:promotion_banner_background_color], "ist ungültig"
  end

  test "promotion banner background color detects light and dark contrast schemes" do
    light_event = events(:published_one)
    dark_event = events(:published_one).dup

    light_event.promotion_banner_background_color = "#F2F7E0"
    dark_event.promotion_banner_background_color = "#18333A"

    assert_predicate light_event, :promotion_banner_background_bright?
    assert_equal "dark", light_event.promotion_banner_text_color_scheme
    assert_not dark_event.promotion_banner_background_bright?
    assert_equal "light", dark_event.promotion_banner_text_color_scheme
  end

  private

  def create_event_image(event:, purpose:)
    image = EventImage.new(
      event: event,
      purpose: purpose,
      alt_text: "Alt",
      sub_text: "Sub"
    )
    image.file.attach(
      io: StringIO.new(File.binread(@fixture_path)),
      filename: "test_image.png",
      content_type: "image/png"
    )
    image.save!
    image
  end

  def capture_sql_queries
    queries = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"
      next if payload[:cached]
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/)

      queries += 1
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end

    queries
  end
end
