require "test_helper"

module Venues
  class LlmFallbackAssignmentTest < ActiveSupport::TestCase
    teardown do
      AppSetting.where(key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY).delete_all
      AppSetting.reset_cache!
    end

    test "does not overwrite an existing venue name or description" do
      event = events(:published_one)
      event.venue_record.update!(description: "Bestehende Beschreibung")
      event.venue_record.update!(external_url: "https://bestehend.example", address: "Bestehende Adresse")
      enrichment = EventLlmEnrichment.new(
        venue: "Andere Venue",
        venue_description: "Neue Beschreibung",
        venue_external_url: "https://neu.example",
        venue_address: "Neue Adresse"
      )

      assert_no_difference("Venue.count") do
        LlmFallbackAssignment.call(event:, enrichment:)
      end

      event.reload
      assert_equal "LKA Longhorn", event.venue
      assert_equal "Bestehende Beschreibung", event.venue_record.description
      assert_equal "https://bestehend.example", event.venue_record.external_url
      assert_equal "Bestehende Adresse", event.venue_record.address
    end

    test "fills blank metadata on an existing matching venue without overwriting present values" do
      event = events(:published_one)
      event.venue_record.update!(
        description: nil,
        external_url: "https://bestehend.example",
        address: nil
      )
      enrichment = EventLlmEnrichment.new(
        venue: "LKA Longhorn",
        venue_description: "Neue Beschreibung",
        venue_external_url: "https://neu.example",
        venue_address: "Neue Adresse"
      )

      assert_no_difference("Venue.count") do
        LlmFallbackAssignment.call(event:, enrichment:)
      end

      event.reload
      assert_equal "LKA Longhorn", event.venue
      assert_equal "Neue Beschreibung", event.venue_record.description
      assert_equal "https://bestehend.example", event.venue_record.external_url
      assert_equal "Neue Adresse", event.venue_record.address
    end

    test "creates and assigns a venue with description when the event has none yet" do
      event = Event.new(
        artist_name: "Neue Band",
        title: "Neues Konzert",
        start_at: Time.zone.local(2026, 7, 1, 20, 0),
        status: "needs_review"
      )
      enrichment = EventLlmEnrichment.new(
        venue: "LLM Club",
        venue_description: "LLM Club Beschreibung",
        venue_external_url: "https://llm-club.example",
        venue_address: "LLM Straße 5, Stuttgart"
      )

      assert_difference("Venue.count", 1) do
        LlmFallbackAssignment.call(event:, enrichment:)
      end

      event.reload
      assert_equal "LLM Club", event.venue
      assert_equal "LLM Club", event.venue_record.name
      assert_equal "LLM Club Beschreibung", event.venue_record.description
      assert_equal "https://llm-club.example", event.venue_record.external_url
      assert_equal "LLM Straße 5, Stuttgart", event.venue_record.address
    end

    test "reuses an existing venue through flexible name matching" do
      venues(:lka_longhorn).update!(description: nil, external_url: nil, address: nil)
      event = Event.new(
        artist_name: "Neue Band",
        title: "Neues Konzert",
        start_at: Time.zone.local(2026, 7, 2, 20, 0),
        status: "needs_review"
      )
      enrichment = EventLlmEnrichment.new(
        venue: "LKA-Longhorn Stuttgart",
        venue_description: "Neue Beschreibung"
      )

      assert_no_difference("Venue.count") do
        LlmFallbackAssignment.call(event:, enrichment:)
      end

      event.reload
      assert_equal venues(:lka_longhorn), event.venue_record
      assert_equal "Neue Beschreibung", event.venue_record.description
    end

    test "reuses canonical venue through configured duplicate mapping" do
      canonical = Venue.create!(name: "Liederhalle Beethoven-Saal", description: nil)
      AppSetting.create!(
        key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY,
        value: [
          {
            "alias" => "KKL Beethoven-Saal Stuttgart",
            "canonical" => "Liederhalle Beethoven-Saal",
            "alias_key" => "kkl beethoven saal",
            "canonical_key" => "liederhalle beethoven saal"
          }
        ]
      )
      event = Event.new(
        artist_name: "Neue Band",
        title: "Neues Konzert",
        start_at: Time.zone.local(2026, 7, 3, 20, 0),
        status: "needs_review"
      )
      enrichment = EventLlmEnrichment.new(
        venue: "KKL Beethoven-Saal Stuttgart",
        venue_description: "Kanonische Beschreibung"
      )

      assert_no_difference("Venue.count") do
        LlmFallbackAssignment.call(event:, enrichment:)
      end

      event.reload
      assert_equal canonical, event.venue_record
      assert_equal "Kanonische Beschreibung", canonical.reload.description
    end
  end
end
