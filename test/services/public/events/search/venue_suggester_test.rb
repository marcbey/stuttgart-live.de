require "test_helper"

class Public::Events::Search::VenueSuggesterTest < ActiveSupport::TestCase
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

  private

  def suggest(query)
    Public::Events::Search::VenueSuggester.call(query)
  end
end
