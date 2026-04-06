require "test_helper"

class StaticPageTest < ActiveSupport::TestCase
  setup do
    StaticPageDefaults.ensure!
  end

  test "generates slug from title" do
    page = StaticPage.create!(
      title: "Über uns",
      kicker: "Info",
      intro: "Kurzbeschreibung",
      body: "<div>Inhalt</div>"
    )

    assert_equal "uber-uns", page.slug
  end

  test "rejects reserved slug for custom pages" do
    page = StaticPage.new(
      slug: "backend",
      title: "Backend FAQ",
      body: "<div>Inhalt</div>"
    )

    assert_not page.valid?
    assert_includes page.errors[:slug], "ist reserviert"
  end

  test "rejects lane landing page slugs for custom pages" do
    page = StaticPage.new(
      slug: "highlights",
      title: "Highlights",
      body: "<div>Inhalt</div>"
    )

    assert_not page.valid?
    assert_includes page.errors[:slug], "ist reserviert"
  end

  test "rejects invalid slug format" do
    page = StaticPage.new(
      slug: "mehr/info",
      title: "Mehr Info",
      body: "<div>Inhalt</div>"
    )

    assert_not page.valid?
    assert_includes page.errors[:slug], "ist ungültig"
  end

  test "requires rich text body" do
    page = StaticPage.new(
      slug: "ohne-inhalt",
      title: "Ohne Inhalt"
    )

    assert_not page.valid?
    assert_includes page.errors[:body], "muss ausgefüllt werden"
  end

  test "system pages keep their fixed slug" do
    page = StaticPage.find_by!(slug: "kontakt")

    page.slug = "neuer-slug"

    assert_not page.valid?
    assert_includes page.errors[:slug], "kann für Systemseiten nicht geändert werden"
  end

  test "system pages cannot be destroyed" do
    page = StaticPage.find_by!(slug: "datenschutz")

    assert_not page.destroy
    assert_includes page.errors[:base], "Systemseiten können nicht gelöscht werden"
  end
end
