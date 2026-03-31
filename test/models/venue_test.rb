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

  test "distinguishes venue variants with meaningful qualifiers" do
    assert_not Venue.same_name?("Im Wizemann", "Im Wizemann (Halle)")
  end

  test "matches kulturquartier proton variants through the match key" do
    assert Venue.same_name?("Kulturquartier - PROTON", "Kulturquartier Stuttgart")
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
