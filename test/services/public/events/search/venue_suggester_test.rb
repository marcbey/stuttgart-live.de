require "test_helper"

class Public::Events::Search::VenueSuggesterTest < ActiveSupport::TestCase
  teardown do
    AppSetting.where(key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY).delete_all
    AppSetting.reset_cache!
  end

  test "finds venues for short infix prefixes case insensitively" do
    results = suggest("Wi")

    assert_includes results.map(&:name), "Im Wizemann"
  end

  test "prefers prefix matches before looser matches" do
    venue = Venue.create!(name: "Wiesbadener Halle")

    results = suggest("Wie")

    assert_equal venue, results.first
  end

  test "finds typo similar venues via trigram matching" do
    Venue.create!(name: "Porsche-Arena")

    results = suggest("Porshe")

    assert_equal "Porsche-Arena", results.first.name
  end

  test "suggests canonical venue for configured duplicate mapping" do
    canonical = Venue.create!(name: "Liederhalle Beethoven-Saal")
    Venue.create!(name: "Liederhalle Beethovensaal")
    configure_venue_duplicate_mapping(
      alias_name: "Liederhalle Beethovensaal",
      canonical_name: canonical.name
    )

    results = suggest("Liederhalle Beethovensaal")

    assert_equal [ canonical ], results
  end

  private

  def suggest(query)
    Public::Events::Search::VenueSuggester.call(query)
  end

  def configure_venue_duplicate_mapping(alias_name:, canonical_name:)
    AppSetting.create!(
      key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY,
      value: [
        {
          "alias" => alias_name,
          "canonical" => canonical_name,
          "alias_key" => Venue.match_key(alias_name),
          "canonical_key" => Venue.match_key(canonical_name)
        }
      ]
    )
    AppSetting.reset_cache!
  end
end
