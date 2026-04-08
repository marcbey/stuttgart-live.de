require "test_helper"

class HomepagePromotionBannerStylesheetTest < ActiveSupport::TestCase
  test "homepage poster banner stylesheet preserves crop positioning" do
    stylesheet = Rails.root.join("app/assets/stylesheets/frontend.tailwind.css").read
    image_rules = stylesheet.scan(/body\.page-public-events-index \.promotion-banner-poster \.promotion-banner-image \{([^}]*)\}/m).flatten
    media_rules = stylesheet.scan(/body\.page-public-events-index \.promotion-banner-poster \.promotion-banner-media \{([^}]*)\}/m).flatten

    assert image_rules.any?, "expected homepage promotion banner image rules"
    assert media_rules.any?, "expected homepage promotion banner media rules"

    image_rules.each do |rule|
      refute_match(/position:\s*static\b/, rule)
      refute_match(/object-fit:\s*contain\b/, rule)
      refute_match(/width:\s*100%\s*!important/, rule)
      refute_match(/height:\s*auto\s*!important/, rule)
    end

    media_rules.each do |rule|
      refute_match(/overflow:\s*visible\b/, rule)
    end
  end
end
