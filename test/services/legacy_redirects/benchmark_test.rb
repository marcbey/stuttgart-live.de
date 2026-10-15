require "test_helper"

class LegacyRedirects::BenchmarkTest < ActiveSupport::TestCase
  test "measures warm and cold local resolver samples without retaining cold state" do
    row = LegacyRedirect.create!(source_path: "/benchmark-old", source_kind: "page", checked_at: Time.current)
    before = row.attributes
    resolver = lambda do |path:, query:|
      LegacyRedirect.find_by!(source_path: path).update!(checked_at: Time.current)
    end
    report = LegacyRedirects::Benchmark.new(paths: [ row.source_path ], samples: 3, resolver: resolver).call
    assert_equal "local", report[:environment]
    assert_equal 3, report[:cold][:samples]
    assert_equal 3, report[:warm][:samples]
    assert report[:cold][:p95_ms] >= 0
    assert_equal before, row.reload.attributes
    assert_equal false, report[:production_verified]
  end
end
