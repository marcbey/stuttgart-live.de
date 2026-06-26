require "test_helper"

class HomepagePromotionBannerStylesheetTest < ActiveSupport::TestCase
  test "homepage poster banner stylesheet preserves crop positioning" do
    stylesheet = Rails.root.join("app/assets/stylesheets/frontend.tailwind.css").read
    image_rules = stylesheet.scan(/body\.page-public-events-index \.promotion-banner-poster \.promotion-banner-image \{([^}]*)\}/m).flatten
    media_rules = stylesheet.scan(/body\.page-public-events-index \.promotion-banner-poster \.promotion-banner-media \{([^}]*)\}/m).flatten
    desktop_image_rules = image_rules.reject { |rule| rule.match?(/position:\s*static\b/) || rule.match?(/object-fit:\s*contain\b/) }

    assert desktop_image_rules.any?, "expected homepage promotion banner desktop image rules"
    assert media_rules.any?, "expected homepage promotion banner media rules"

    desktop_image_rules.each do |rule|
      refute_match(/position:\s*static\b/, rule)
      refute_match(/object-fit:\s*contain\b/, rule)
      refute_match(/width:\s*100%\s*!important/, rule)
      refute_match(/height:\s*auto\s*!important/, rule)
    end

    media_rules.each do |rule|
      refute_match(/overflow:\s*visible\b/, rule)
    end
  end

  test "mobile promotion banners render taller image crops" do
    stylesheet = Rails.root.join("app/assets/stylesheets/frontend.tailwind.css").read
    mobile_stylesheet = stylesheet.split("@media (max-width: 720px)").second

    assert_match(/position:\s*static\s*!important/, mobile_stylesheet)
    assert_match(/width:\s*100%\s*!important/, mobile_stylesheet)
    assert_match(/height:\s*100%\s*!important/, mobile_stylesheet)
    assert_match(/object-fit:\s*cover\s*!important/, mobile_stylesheet)
  end
end
