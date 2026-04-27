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

    assert_equal "Kulturquartier (Proton)", venue.name
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
    assert Venue.same_name?("Kulturquartier - PROTON", "Kulturquartier (Proton)")
  end

  test "normalizes schleyer halle aliases to the official venue name" do
    assert_equal "Hanns-Martin-Schleyer-Halle", Venue.normalize_name("Schleyer-Halle")
    assert_equal "Hanns-Martin-Schleyer-Halle", Venue.normalize_name("Schleyer-Halle Stuttgart")
  end

  test "normalizes hospitalhof aliases to the shorter venue name" do
    assert_equal "Hospitalhof", Venue.normalize_name("Hospitalhof Stuttgart")
    assert_equal "Hospitalhof", Venue.normalize_name("Hospitalhof, Paul-Lechler-Saal")
  end

  test "normalizes kulinarium aliases to the preferred venue name" do
    assert_equal "Kulinarium an der Glems", Venue.normalize_name("Kulinarium an der Glems/Römerhof")
  end

  test "normalizes kulturquartier aliases to the proton venue name" do
    assert_equal "Kulturquartier (Proton)", Venue.normalize_name("Kulturquartier")
    assert_equal "Kulturquartier (Proton)", Venue.normalize_name("Kulturquartier Stuttgart ( the Club)")
  end

  test "normalizes schraglage aliases to the preferred venue name" do
    assert_equal "Schräglage", Venue.normalize_name("Schräglage Club")
    assert_equal "Schräglage", Venue.normalize_name("Schräglage Stuttgart")
  end

  test "normalizes fitz aliases to the preferred venue name" do
    assert_equal "FITZ! Figurentheater", Venue.normalize_name("FITZ")
    assert_equal "FITZ! Figurentheater", Venue.normalize_name("FITZ Das Theater animierter Formen")
  end

  test "normalizes das k room aliases to the preferred venue name" do
    assert_equal "Das K-Kultur-und Kongresszentrum", Venue.normalize_name("Das K - Kultur- und Kongresszentrum - Theatersaal")
    assert_equal "Das K-Kultur-und Kongresszentrum", Venue.normalize_name("Das K – Kulturzentrum (Festsaal)")
  end

  test "normalizes scala ludwigsburg aliases to the preferred venue name" do
    assert_equal "Scala Ludwigsburg", Venue.normalize_name("Scala")
    assert_equal "Scala Ludwigsburg", Venue.normalize_name("Scala Theater Ludwigsburg")
    assert_equal "Scala Ludwigsburg", Venue.normalize_name("Scala Theater Ludwigburg")
    assert_equal "Scala Ludwigsburg", Venue.normalize_name("Scala Ludwigsburg")
  end

  test "normalizes liederhalle hall aliases to the canonical kkl hall names" do
    assert_equal "Kultur- und Kongresszentrum Liederhalle Beethoven-Saal", Venue.normalize_name("Liederhalle Beethovensaal")
    assert_equal "Kultur- und Kongresszentrum Liederhalle Mozart-Saal", Venue.normalize_name("Mozartsaal Kultur- und Kongresszentrum Liederhalle Stuttgart")
    assert_equal "Kultur- und Kongresszentrum Liederhalle Hegel-Saal", Venue.normalize_name("Liederhalle Stuttgart - Hegelsaal")
    assert_equal "Kultur- und Kongresszentrum Liederhalle Silcher-Saal", Venue.normalize_name("Liederhalle Silchersaal")
    assert_equal "Kultur- und Kongresszentrum Liederhalle Schiller-Saal", Venue.normalize_name("Liederhalle Schiller-Saal")
  end

  test "matches schleyer halle alias names to the official venue name" do
    assert Venue.same_name?("Schleyer-Halle", "Hanns-Martin-Schleyer-Halle")
    assert Venue.same_name?("Schleyer-Halle Stuttgart", "Hanns-Martin-Schleyer-Halle")
    assert_not Venue.same_name?("Schleyer-Halle Saal 4 Stuttgart", "Hanns-Martin-Schleyer-Halle")
  end

  test "matches hospitalhof alias names but keeps distinct subvenues separate" do
    assert Venue.same_name?("Hospitalhof Stuttgart", "Hospitalhof")
    assert Venue.same_name?("Hospitalhof, Paul-Lechler-Saal", "Hospitalhof")
    assert_not Venue.same_name?("Hospitalhof, Rosengarten", "Hospitalhof")
  end

  test "matches kulinarium aliases to the preferred venue name" do
    assert Venue.same_name?("Kulinarium an der Glems/Römerhof", "Kulinarium an der Glems")
  end

  test "matches kulturquartier aliases to the proton venue name" do
    assert Venue.same_name?("Kulturquartier", "Kulturquartier (Proton)")
    assert Venue.same_name?("Kulturquartier Stuttgart ( the Club)", "Kulturquartier (Proton)")
  end

  test "matches schraglage aliases to the preferred venue name" do
    assert Venue.same_name?("Schräglage Club", "Schräglage")
    assert Venue.same_name?("Schräglage Stuttgart", "Schräglage")
  end

  test "matches fitz aliases to the preferred venue name" do
    assert Venue.same_name?("FITZ", "FITZ! Figurentheater")
    assert Venue.same_name?("FITZ Das Theater animierter Formen", "FITZ! Figurentheater")
  end

  test "matches das k room aliases to the preferred venue name" do
    assert Venue.same_name?("Das K - Kultur- und Kongresszentrum - Festsaal", "Das K-Kultur-und Kongresszentrum")
    assert Venue.same_name?("Das K – Kulturzentrum (Festsaal)", "Das K-Kultur-und Kongresszentrum")
  end

  test "matches scala ludwigsburg aliases to the preferred venue name" do
    assert Venue.same_name?("Scala", "Scala Ludwigsburg")
    assert Venue.same_name?("Scala Theater Ludwigsburg", "Scala Ludwigsburg")
    assert Venue.same_name?("Scala Theater Ludwigburg", "Scala Ludwigsburg")
  end

  test "matches liederhalle hall aliases but keeps the generic house venue separate" do
    assert Venue.same_name?("Liederhalle Beethovensaal", "Kultur- und Kongresszentrum Liederhalle Beethoven-Saal")
    assert Venue.same_name?("Liederhalle Mozartsaal", "Kultur- und Kongresszentrum Liederhalle Mozart-Saal")
    assert Venue.same_name?("Liederhalle Hegelsaal", "Kultur- und Kongresszentrum Liederhalle Hegel-Saal")
    assert_not Venue.same_name?("Kultur- und Kongresszentrum Liederhalle", "Kultur- und Kongresszentrum Liederhalle Hegel-Saal")
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
