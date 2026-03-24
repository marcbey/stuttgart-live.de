require "test_helper"

class Backend::Presenters::BulkImporterTest < ActiveSupport::TestCase
  test "extracts presenter names from filenames" do
    assert_equal "Foo Bar", Backend::Presenters::BulkImporter.extract_name("Foo-Bar.png")
    assert_equal "ACME Booking", Backend::Presenters::BulkImporter.extract_name("ACME_Booking.svg")
    assert_equal "Live Nation", Backend::Presenters::BulkImporter.extract_name("  Live   Nation  .webp")
  end

  test "flags duplicate normalized names within one batch" do
    result = Backend::Presenters::BulkImporter.new(
      files: [
        png_upload(filename: "alpha-band.png"),
        png_upload(filename: "alpha_band.png")
      ]
    ).call

    assert_equal 0, result.created
    assert_equal 0, result.updated
    assert_equal 2, result.failed
    assert_equal 2, result.errors.size
    assert result.errors.all? { |message| message.include?("denselben Präsentator-Namen") }
  end

  test "rejects non image uploads" do
    result = Backend::Presenters::BulkImporter.new(
      files: [ text_upload(filename: "presenter.txt") ]
    ).call

    assert_equal 0, result.created
    assert_equal 0, result.updated
    assert_equal 1, result.failed
    assert_includes result.errors.first, "Datei muss ein Bild sein."
  end

  private

  def text_upload(filename:)
    Rack::Test::UploadedFile.new(
      StringIO.new("kein bild"),
      "text/plain",
      original_filename: filename
    )
  end
end
