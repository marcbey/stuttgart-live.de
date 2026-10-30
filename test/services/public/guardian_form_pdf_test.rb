require "test_helper"
require "open3"

class Public::GuardianFormPdfTest < ActiveSupport::TestCase
  test "renders two A4 pages with event details, complete signature labels and guidance" do
    pdf = Public::GuardianFormPdf.new(
      event: "MAMMA MIA! - Das Original-Musical", venue: "Porsche-Arena", date: "2027-05-05"
    ).render
    text = extract_text(pdf)
    pages = text.split("\f")

    assert_equal 2, pdf.scan(%r{/Type /Page\b}).size
    assert_equal 2, pages.size
    assert_includes pages.first, "MAMMA MIA! - Das Original-Musical"
    assert_includes pages.first, "05.05.2027"
    assert_includes pages.first, "Porsche-Arena"
    assert_includes pages.first, "02 Minderjährige Person"
    assert_includes pages.first, "Unterschrift\nErziehungsberechtigte Person"
    assert_includes pages.first, "Unterschrift\nBegleitperson"
    assert_includes pages.last, "Erziehungsbeauftragte"
    assert_includes pages.last.squish, "Eine gesonderte Beauftragung ist dann nicht notwendig."
    assert_includes pdf, "/AcroForm"
    assert_equal 10, pdf.scan(%r{/Subtype /Widget\b}).size
    assert_not_includes text, "Backend"
    assert_not_includes text, "ALLE EVENTS"
  end

  test "blank and invalid event details leave fields available for manual entry" do
    [ {}, { date: "2026-02-31" }, { event: [ "bad" ], venue: { name: "bad" }, date: [ "bad" ] } ].each do |params|
      pdf = Public::GuardianFormPdf.new(**params).render

      assert_equal 2, pdf.scan(%r{/Type /Page\b}).size
      assert_equal 13, pdf.scan(%r{/Subtype /Widget\b}).size
      assert_not_includes extract_text(pdf), "bad"
    end
  end

  test "long event details and special characters stay within two pages" do
    pdf = Public::GuardianFormPdf.new(event: "ÄÖÜ & <Test> " * 30, venue: "Große Spielstätte " * 30).render

    assert_equal 2, pdf.scan(%r{/Type /Page\b}).size
    assert_includes extract_text(pdf), "ÄÖÜ & <Test>"
  end

  private

  def extract_text(pdf)
    text, error, status = Open3.capture3("pdftotext", "-", "-", stdin_data: pdf, binmode: true)
    assert status.success?, error
    text.force_encoding(Encoding::UTF_8)
  end
end
