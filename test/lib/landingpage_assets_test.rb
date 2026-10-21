require "test_helper"
require "rack/mock"
require "uri"

class LandingpageAssetsTest < ActiveSupport::TestCase
  %w[ovo mamma-mia].each do |page|
    [ "", "/", "/index.html" ].each do |suffix|
      test "#{page} assets load when opened at /#{page}#{suffix}" do
        request = Rack::MockRequest.new(ActionDispatch::Static.new(
          ->(_env) { [ 404, {}, [ "missing" ] ] }, Rails.root.join("public").to_s
        ))
        url = URI("https://example.test/#{page}#{suffix}")
        response = request.get(url.path)
        assert_equal 200, response.status

        document = Nokogiri::HTML(response.body)
        document.css("img[src], script[src], link[rel='stylesheet'][href]").each do |element|
          source = element["src"] || element["href"]
          asset = URI.join(url.to_s, source)
          next unless asset.host == url.host

          result = request.get(asset.path)
          assert_equal 200, result.status, "#{url.path}: #{source} resolved to missing #{asset.path}"
          refute_match %r{text/html}, result["content-type"], "Asset returned HTML: #{asset.path}"
        end
      end
    end
  end
end
