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
    renderer = Meta::SocialCardRenderer.new
    renderer.define_singleton_method(:measure_text) do |text, font_name:, font_size:|
      text.to_s.length * 20
    end

    variant = Meta::SocialCardRenderer::VARIANTS.fetch(:facebook)

    artist_lines = renderer.send(
      :wrap_lines,
      "The Astonishingly Long Artist Name That Absolutely Must Not Overflow The Card Layout Or Continue Into Yet Another Needlessly Long Clause",
      font_name: Meta::SocialCardRenderer::ARTIST_FONT_NAME,
      font_size: variant.artist_font_size,
      max_width: renderer.send(:text_width_for, variant),
      max_lines: variant.artist_max_lines,
      uppercase: true
    )

    venue_text = renderer.send(
      :fitted_meta_venue_text,
      "MHP Arena Ludwigsburg With A Venue Name That Definitely Will Not Fit In One Row Even If Font Metrics Shift Slightly Between Operating Systems",
      date_text: "18.02.2027",
      variant:
    )

    assert artist_lines.last.end_with?("...")
    assert venue_text.end_with?("...")
  end
end
