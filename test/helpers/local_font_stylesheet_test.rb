require "test_helper"

class LocalFontStylesheetTest < ActiveSupport::TestCase
  test "frontend stylesheet keeps typography rules but delegates font-face generation to the layout" do
    stylesheet = Rails.root.join("app/assets/stylesheets/frontend.tailwind.css").read

    refute_match(/@font-face|archivo-narrow|oswald-|bebas-neue-400/, stylesheet)
    refute_match(/fonts\.googleapis\.com|fonts\.gstatic\.com/, stylesheet)
    refute_match(/font-weight:\s*600\b/, stylesheet)
  end

  test "backend stylesheet keeps typography rules but delegates font-face generation to the layout" do
    stylesheet = Rails.root.join("app/assets/stylesheets/backend.tailwind.css").read

    refute_match(/@font-face|archivo-narrow|oswald-|bebas-neue-400/, stylesheet)
    refute_match(/font-weight:\s*600\b/, stylesheet)
  end
end
