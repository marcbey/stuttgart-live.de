require "test_helper"

class LegacyRedirects::ReportTest < ActiveSupport::TestCase
  test "reports public redirects separately from local current paths and crawl errors" do
    LegacyRedirect.create!(source_path: "/old-report", source_kind: "page", status: "redirect", target_path: "/events")
    LegacyRedirect.create!(source_path: "/events", source_kind: "page")
    LegacyRedirect.create!(source_path: "/broken-report", source_kind: "page", source_metadata: { crawl_error: "HTTP 503" })
    LegacyRedirect.create!(source_path: "/disabled-report", source_kind: "page", status: "disabled")
    report = LegacyRedirects::Report.new.call
    states = report.fetch(:rows).index_by { |row| row[:source_path] }
    assert_equal "redirect", states["/old-report"][:result]
    assert_equal "current_public_200", states["/events"][:result]
    assert_equal "crawl_error", states["/broken-report"][:result]
    assert_equal "disabled", states["/disabled-report"][:result]
    assert_equal false, report[:http_validated]
    Dir.mktmpdir do |directory|
      paths = LegacyRedirects::Report.new.write(directory: directory)
      assert JSON.parse(File.read(paths[:json])).fetch("rows").any?
      assert_includes File.read(paths[:csv]), "source_path"
    end
  end

  test "CSV escapes embedded comma newline and quotes without formula execution" do
    LegacyRedirect.create!(source_path: "/csv-escaping", source_kind: "page", source_metadata: { crawl_error: "=bad,\n\"quoted\"" })
    Dir.mktmpdir do |directory|
      csv = File.read(LegacyRedirects::Report.new.write(directory: directory)[:csv])
      assert_includes csv, %Q("'=bad,\n""quoted"""\r\n)
    end
  end
end
