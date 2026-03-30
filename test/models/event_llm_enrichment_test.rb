require "test_helper"

class EventLlmEnrichmentTest < ActiveSupport::TestCase
  test "normalizes attributes and enforces one enrichment per event" do
    enrichment = EventLlmEnrichment.create!(
      event: events(:published_one),
      source_run: import_runs(:one),
      genre: [ " Jazz ", "", "Jazz" ],
      venue: " LKA Longhorn ",
      artist_description: " Artist ",
      event_description: " Event ",
      venue_description: " Venue ",
      venue_external_url: " https://venue.example/demo ",
      venue_address: " Venue Straße 1, Stuttgart ",
      youtube_link: " https://youtube.example/demo ",
      instagram_link: " https://instagram.example/demo ",
      homepage_link: " https://homepage.example/demo ",
      facebook_link: " https://facebook.example/demo ",
      model: " gpt-5-mini ",
      prompt_version: " v1 ",
      raw_response: { "event_id" => events(:published_one).id }
    )

    assert_equal [ "Jazz" ], enrichment.genre
    assert_equal "LKA Longhorn", enrichment.venue
    assert_equal "https://venue.example/demo", enrichment.venue_external_url
    assert_equal "Venue Straße 1, Stuttgart", enrichment.venue_address
    assert_equal "gpt-5-mini", enrichment.model
    assert_equal "v1", enrichment.prompt_version

    duplicate = enrichment.dup
    duplicate.source_run = import_runs(:two)

    assert_not duplicate.valid?
    assert duplicate.errors.added?(:event_id, :taken, value: events(:published_one).id)
  end

  test "normalizes invalid raw_response to empty hash" do
    enrichment = EventLlmEnrichment.new(
      event: events(:published_one),
      source_run: import_runs(:one),
      model: "gpt-5-mini",
      prompt_version: "v1",
      raw_response: []
    )

    assert enrichment.valid?
    assert_equal({}, enrichment.raw_response)
  end

  test "genre_list assigns normalized genres" do
    enrichment = EventLlmEnrichment.new(
      event: events(:published_one),
      source_run: import_runs(:one),
      model: "gpt-5-mini",
      prompt_version: "v1",
      raw_response: {}
    )

    enrichment.genre_list = " Indie \nRock, Pop ; Rock "

    assert enrichment.valid?
    assert_equal [ "Indie", "Rock", "Pop" ], enrichment.genre
    assert_equal " Indie \nRock, Pop ; Rock ", enrichment.genre_list
  end
end
