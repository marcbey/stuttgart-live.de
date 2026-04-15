require "test_helper"

class Meta::SocialCardRendererTest < ActiveSupport::TestCase
  test "renders all card variants in the expected dimensions" do
    background_blob = create_uploaded_blob(filename: "social-card-background.png", width: 1600, height: 1200, rgb: [ 18, 45, 51 ])
    background_source = Meta::EventSocialPostDraftBuilder::BackgroundSource.new(
      source_type: :attachment,
      attachment: background_blob,
      remote_url: nil,
      focus_x: 50,
      focus_y: 50,
      zoom: 100,
      source_label: "test"
    )

    rendered_cards = Meta::SocialCardRenderer.new.render_set(
      background_source:,
      card_payload: {
        artist_name: "Mike Oldfield's Tubular Bells",
        title: "The Best of Tubular Bells I, II & III",
        date_label: "09.09.2026",
        venue_label: "Liederhalle Hegelsaal"
      },
      slug: "tubular-bells"
    )

    assert_equal [ 1080, 1080 ], image_dimensions(rendered_cards[:preview].binary)
    assert_equal [ 1080, 1080 ], image_dimensions(rendered_cards[:facebook].binary)
    assert_equal [ 1080, 1350 ], image_dimensions(rendered_cards[:instagram].binary)
  end

  test "truncates long artist, title and venue text with ellipsis" do
    background_blob = create_uploaded_blob(filename: "truncate-background.png", width: 1800, height: 1600, rgb: [ 0, 0, 0 ])
    background_source = Meta::EventSocialPostDraftBuilder::BackgroundSource.new(
      source_type: :attachment,
      attachment: background_blob,
      remote_url: nil,
      focus_x: 50,
      focus_y: 50,
      zoom: 100,
      source_label: "test"
    )

    rendered_cards = Meta::SocialCardRenderer.new.render_set(
      background_source:,
      card_payload: {
        artist_name: "The Astonishingly Long Artist Name That Absolutely Must Not Overflow The Card Layout Or Continue Into Yet Another Needlessly Long Clause",
        title: "An Even Longer Event Title That Needs To Be Cut Cleanly Before It Breaks The Highlight Style And Keeps Running Far Beyond A Single Reasonable Line",
        date_label: "18.02.2027",
        venue_label: "MHP Arena Ludwigsburg With A Venue Name That Definitely Will Not Fit In One Row Even If Font Metrics Shift Slightly Between Operating Systems"
      },
      slug: "long-card"
    )

    assert rendered_cards[:facebook].artist_lines.last.end_with?("...")
    assert rendered_cards[:facebook].title_lines.first.end_with?("...")
    assert rendered_cards[:facebook].venue_text.end_with?("...")
  end
end
