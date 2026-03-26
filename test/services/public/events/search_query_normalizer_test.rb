require "test_helper"

class Public::Events::SearchQueryNormalizerTest < ActiveSupport::TestCase
  test "normalizes german umlauts and punctuation consistently" do
    assert_equal(
      "die aerzte ac dc",
      Public::Events::SearchQueryNormalizer.normalize("Die Ärzte: AC/DC")
    )
  end

  test "builds wildcard patterns for normalized query variants" do
    assert_equal(
      [ "%die%aerzte%live%", "%die%ärzte%live%" ],
      Public::Events::SearchQueryNormalizer.wildcard_patterns("Die Ärzte Live!")
    )
  end

  test "collapses punctuation only input to an empty string" do
    assert_equal "", Public::Events::SearchQueryNormalizer.normalize("... !!!")
  end
end
