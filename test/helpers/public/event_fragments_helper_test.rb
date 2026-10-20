require "test_helper"

class Public::EventFragmentsHelperTest < ActionView::TestCase
  include Public::EventsHelper

  setup do
    travel_to Time.zone.local(2026, 4, 15, 12)
    @event = events(:published_one)
    @browse_state = Public::Events::BrowseState.new({ "filter" => "all" })
    AppSetting.reset_cache!
  end

  teardown do
    AppSetting.reset_cache!
    travel_back
  end

  test "fragment keys reuse loaded records without association queries" do
    event = loaded_event
    AppSetting.venue_duplicate_mappings
    Merging::ProviderPriorityMap.call
    queries = []
    callback = ->(notification) { queries << notification.payload[:sql] unless notification.payload[:name] == "SCHEMA" }
    key = nil
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { key = fragment_key(event) }

    assert key.present?
    assert_empty queries
    assert_nil fragment_key(@event.reload), "Unloaded associations must bypass caching"
  end

  test "render context and browse parameters cannot share fragments" do
    event = loaded_event
    key = fragment_key(event)
    [ { variant: "feature" }, { prioritize_first_image: true }, { image_loading: "eager" },
      { strict_proxy: true }, { effective_series_ids: [ 9 ], series_counts_by_id: { 9 => 3 } },
      { dom_id_prefix: "saved" }, { next_cursor: "cursor-two" }, { show_expired_status: false } ].each do |context|
      assert_not_equal key, fragment_key(event, context: context)
    end
    [ { "q" => "Konzert" }, { "event_date" => "2026-06-01" }, { "filter" => "sks" }, { "page" => "2" } ].each do |params|
      assert_not_equal key, fragment_key(event, browse_state: Public::Events::BrowseState.new(params))
    end
  end

  test "time-sensitive ticket status changes exactly when an event starts" do
    travel_to @event.start_at - 1.second
    key = fragment_key(loaded_event)
    travel_to @event.start_at + 1.second
    assert_not_equal key, fragment_key(loaded_event)
  end

  test "media changes and processed variant readiness invalidate the fragment" do
    image = @event.event_images.build(purpose: EventImage::PURPOSE_SLIDER)
    image.file.attach(create_uploaded_blob)
    image.save!
    key = fragment_key(loaded_event)
    variant = image.file.blob.variant_records.create!(variation_digest: "newly-ready-variant")
    assert_not_equal key, fragment_key(loaded_event)

    key = fragment_key(loaded_event)
    variant.image.attach(create_uploaded_blob(filename: "ready-variant.png"))
    assert_not_equal key, fragment_key(loaded_event), "Attaching a ready derivative to an existing variant must invalidate its fallback"

    key = fragment_key(loaded_event)
    travel 1.second do
      image.update!(alt_text: "Neues Bild")
    end
    assert_not_equal key, fragment_key(loaded_event)
  end

  test "mapped venue keys include canonical row changes without repeated queries" do
    canonical = venues(:im_wizemann)
    AppSetting.create!(key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY, value: [ { "alias" => @event.venue_record.name, "canonical" => canonical.name } ])
    AppSetting.reset_cache!
    key = fragment_key(loaded_event)
    assert key.present?
    queries = []
    event = loaded_event
    callback = ->(notification) { queries << notification.payload[:sql] unless notification.payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { assert_equal key, fragment_key(event) }
    assert_empty queries

    travel 1.second do
      canonical.touch
    end
    Current.venue_match_key_index = nil
    assert_not_equal key, fragment_key(loaded_event)
  end

  test "ambient host protocol and media mode isolate fragment markup" do
    event = loaded_event
    key = fragment_key(event)
    request.set_header("HTTP_HOST", "russ-live.de")
    assert_not_equal key, fragment_key(event)
    key = fragment_key(event)
    self.request = ActionController::TestRequest.create(controller.class)
    request.set_header("HTTP_HOST", "russ-live.de")
    request.set_header("HTTPS", "on")
    assert_not_equal key, fragment_key(event)

    key = fragment_key(event)
    original_config = Rails.configuration.x.media_proxy
    Rails.configuration.x.media_proxy = ActiveSupport::OrderedOptions.new.tap do |config|
      config.enabled = !PublicMediaUrl.enabled?
      config.secret = "fragment-test-signing-secret"
    end
    assert_not_equal key, fragment_key(event)
  ensure
    Rails.configuration.x.media_proxy = original_config if original_config
  end

  test "manual offers omit irrelevant priority changes even with imported alternatives" do
    @event.event_offers.create!(source: "manual", source_event_id: "manual-fragment", priority_rank: 0)
    key = fragment_key(loaded_event)
    provider_priorities(:easyticket).update!(priority_rank: 30)
    Current.provider_priority_map = nil

    assert_equal key, fragment_key(loaded_event)
  end

  private

  def loaded_event
    Event.preload(:genres, :venue_record, :event_offers, :import_event_images,
      event_images: { file_attachment: { blob: { variant_records: { image_attachment: :blob } } } }).find(@event.id)
  end

  def fragment_key(event, context: {}, browse_state: @browse_state)
    public_events_fragment_cache_key(section: "modern-grid", events: [ event ], browse_state: browse_state, context: context)
  end
end
