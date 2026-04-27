require "test_helper"

class VenueTest < ActiveSupport::TestCase
  test "requires a unique name" do
    venue = Venue.new(name: "  Im Wizemann  ")

    assert_not venue.valid?
    assert venue.errors[:name].any?
  end

  test "normalizes kulturquartier venue names" do
    venue = Venue.new(name: "Kulturquartier - PROTON")

    venue.valid?

    assert_equal "Kulturquartier", venue.name
  end

  test "builds the same match key for redundant stuttgart suffix variants" do
    assert_equal Venue.match_key("Porsche-Arena"), Venue.match_key("Porsche Arena Stuttgart")
    assert_equal Venue.match_key("LKA-Longhorn"), Venue.match_key("LKA-Longhorn Stuttgart")
    assert_equal Venue.match_key("Im Wizemann (Halle)"), Venue.match_key("Im Wizemann (Halle) Stuttgart")
  end

  test "builds the same match key for apostrophe variants with stuttgart suffix" do
    assert_equal Venue.match_key("Goldmark's"), Venue.match_key("Goldmark´s Stuttgart")
  end

  test "distinguishes venue variants with meaningful qualifiers" do
    assert_not Venue.same_name?("Im Wizemann", "Im Wizemann (Halle)")
  end

  test "matches kulturquartier proton variants through the match key" do
    assert Venue.same_name?("Kulturquartier - PROTON", "Kulturquartier Stuttgart")
  end

  test "normalizes schleyer halle aliases to the official venue name" do
    assert_equal "Hanns-Martin-Schleyer-Halle", Venue.normalize_name("Schleyer-Halle")
    assert_equal "Hanns-Martin-Schleyer-Halle", Venue.normalize_name("Schleyer-Halle Stuttgart")
  end

  test "matches schleyer halle alias names to the official venue name" do
    assert Venue.same_name?("Schleyer-Halle", "Hanns-Martin-Schleyer-Halle")
    assert Venue.same_name?("Schleyer-Halle Stuttgart", "Hanns-Martin-Schleyer-Halle")
    assert_not Venue.same_name?("Schleyer-Halle Saal 4 Stuttgart", "Hanns-Martin-Schleyer-Halle")
  end

  test "allows blank logo but validates uploaded images" do
    venue = Venue.new(name: "Neue Venue")

    assert venue.valid?

    venue.logo.attach(
      io: StringIO.new("not-an-image"),
      filename: "venue.txt",
      content_type: "text/plain"
    )

    assert_not venue.valid?
    assert_includes venue.errors[:logo], "muss ein Bild sein"
  end

  test "cannot be destroyed while events are assigned" do
    venue = venues(:im_wizemann)

    assert_not venue.destroy
    assert venue.errors[:base].any?
  end
end
