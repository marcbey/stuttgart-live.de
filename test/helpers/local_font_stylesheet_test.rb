require "test_helper"

class LocalFontStylesheetTest < ActiveSupport::TestCase
  test "Oswald browser fonts are valid local WOFF2 assets with TTF sources retained" do
    [ 300, 400 ].each do |weight|
      browser_font = Rails.root.join("app/assets/fonts/oswald-#{weight}.woff2")

      assert browser_font.file?, "expected a local WOFF2 asset for Oswald #{weight}"
      assert_equal "wOF2", browser_font.binread(4)
      assert Rails.application.assets.load_path.find("oswald-#{weight}.woff2")
      assert Rails.root.join("app/assets/fonts/oswald-#{weight}.ttf").file?
    end
  end

  test "frontend stylesheet keeps typography rules but delegates font-face generation to the layout" do
    stylesheet = Rails.root.join("app/assets/stylesheets/frontend.tailwind.css").read

    refute_match(/@font-face|archivo-narrow|oswald-/, stylesheet)
    refute_match(/fonts\.googleapis\.com|fonts\.gstatic\.com/, stylesheet)
  end

  test "backend stylesheet keeps typography rules but delegates font-face generation to the layout" do
    stylesheet = Rails.root.join("app/assets/stylesheets/backend.tailwind.css").read

    refute_match(/@font-face|archivo-narrow|oswald-/, stylesheet)
  end
end
