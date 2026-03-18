require "test_helper"

class Merging::ArtistNameNormalizerTest < ActiveSupport::TestCase
  test "normalizes support suffixes consistently" do
    assert_equal(
      Merging::ArtistNameNormalizer.normalize("Band X"),
      Merging::ArtistNameNormalizer.normalize("Band X + Support")
    )
  end

  test "provides significant tokens for concert suffix names" do
    assert_equal(
      %w[vier pianisten],
      Merging::ArtistNameNormalizer.significant_tokens("Vier Pianisten - Ein Konzert")
    )
  end

  test "provides significant tokens for orchestra suffix names" do
    assert_equal(
      %w[gregory porter],
      Merging::ArtistNameNormalizer.significant_tokens("Gregory Porter & Orchestra")
    )
  end
end
