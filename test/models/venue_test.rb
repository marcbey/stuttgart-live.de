require "test_helper"

class VenueTest < ActiveSupport::TestCase
  teardown do
    AppSetting.where(key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY).delete_all
    AppSetting.reset_cache!
  end

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

  test "resolves configured duplicate mapping to existing canonical venue" do
    canonical = Venue.create!(name: "Liederhalle Beethoven-Saal")
    AppSetting.create!(
      key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY,
      value: [
        {
          "alias" => "KKL Beethoven-Saal Stuttgart",
          "canonical" => "Liederhalle Beethoven-Saal",
          "alias_key" => "kkl beethoven saal",
          "canonical_key" => "liederhalle beethoven saal"
        },
        {
          "alias" => "Liederhalle Beethovensaal",
          "canonical" => "Liederhalle Beethoven-Saal",
          "alias_key" => "liederhalle beethovensaal",
          "canonical_key" => "liederhalle beethoven saal"
        }
      ]
    )

    assert_equal canonical, Venues::Resolver.call(name: "KKL Beethoven-Saal Stuttgart")
    assert_equal canonical, Venues::Resolver.call(name: "Liederhalle Beethovensaal")
  end

  test "creates and resolves missing canonical venue for duplicate mapping" do
    AppSetting.create!(
      key: AppSetting::VENUE_DUPLICATE_MAPPINGS_KEY,
      value: [
        {
          "alias" => "KKL Beethoven-Saal Stuttgart",
          "canonical" => "Liederhalle Beethoven-Saal",
          "alias_key" => "kkl beethoven saal",
          "canonical_key" => "liederhalle beethoven saal"
        }
      ]
    )

    venue = Venues::Resolver.call(name: "KKL Beethoven-Saal Stuttgart")

    assert_predicate venue, :persisted?
    assert_equal "Liederhalle Beethoven-Saal", venue.name
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
