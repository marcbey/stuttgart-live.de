require "test_helper"

class Public::Events::Search::GenreSuggesterTest < ActiveSupport::TestCase
  test "finds rock by normalized prefix" do
    suggestions = suggest("rock")

    assert_equal "Rock & Alternative", suggestions.first.name
    assert_equal "/rock-alternative", suggestions.first.path
  end

  test "finds hip hop and rnb variants" do
    assert_equal "Hip-Hop & R’n’B", suggest("hip hop").first.name
    assert_equal "Hip-Hop & R’n’B", suggest("rnb").first.name
  end

  test "finds genre by ascii slug variant" do
    suggestions = suggest("fuhrungen")

    assert_equal "Kultur, Führungen & Touren", suggestions.first.name
  end

  test "orders prefix matches before infix matches" do
    suggestions = suggest("s")

    assert_equal "Schlager & Volksmusik", suggestions.first.name
    assert_not_equal "Pop, Indie & Singer-Songwriter", suggestions.first.name
  end

  test "filters non routeable genre slugs" do
    StaticPage.create!(
      slug: "rock-alternative",
      title: "Rock Alternative Landing",
      intro: "Intro",
      body: "<div>Eigene Seite</div>"
    )

    suggestions = suggest("rock")

    assert_empty suggestions
  end

  private

  def suggest(query)
    Public::Events::Search::GenreSuggester.call(query)
  end
end
