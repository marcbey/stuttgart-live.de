require "test_helper"

class Public::Events::Search::GenreSuggesterTest < ActiveSupport::TestCase
  test "returns default suggestions for blank query" do
    suggestions = suggest("")

    assert_equal [
      "Pop, Indie & Singer-Songwriter",
      "Rock & Alternative",
      "Metal, Punk & Hardcore",
      "Hip-Hop & R’n’B",
      "Electronic Music & EDM",
      "Jazz, Blues & Soul",
      "Klassik & Oper",
      "Musical & Theater"
    ], suggestions.map(&:name)
    assert_equal [
      "/pop-indie-singer-songwriter",
      "/rock-alternative",
      "/metal-punk-hardcore",
      "/hip-hop-r-n-b",
      "/electronic-music-edm",
      "/jazz-blues-soul",
      "/klassik-oper",
      "/musical-theater"
    ], suggestions.map(&:path)
  end

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

  test "batches route checks for default and matching suggestions" do
    [ "", "s" ].each do |query|
      queries = []
      callback = lambda do |event|
        queries << event.payload[:sql].to_s unless event.payload[:cached] || event.payload[:name] == "SCHEMA"
      end
      suggestions = nil
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { suggestions = suggest(query) }

      assert_operator suggestions.size, :>=, 3
      assert_empty queries.grep(/"genres"\."slug" =|"static_pages"\."slug" =/)
      assert_operator queries.grep(/SELECT.*FROM "(?:genres|static_pages)"/m).size, :<=, 3
    end
  end

  private

  def suggest(query)
    Public::Events::Search::GenreSuggester.call(query)
  end
end
