require "test_helper"

class Public::EventPreviewMetadataTest < ActionView::TestCase
  include Public::EventsHelper

  test "preview metadata falls back to the city when the location is missing" do
    render partial: "public/events/search_overlay_event", locals: { event: Event.new(slug: "unknown-venue", city: "Esslingen"), browse_state: Public::Events::BrowseState.new({}) }

    assert_select ".public-search-result-venue", text: "Esslingen"
  end

  test "preview metadata explains an unknown location without empty separators" do
    render partial: "public/events/search_overlay_event", locals: { event: Event.new(slug: "unknown-venue"), browse_state: Public::Events::BrowseState.new({}) }

    assert_select ".public-search-result-venue", text: "Ort wird noch bekannt gegeben"
    assert_select "time", count: 0
  end
end
