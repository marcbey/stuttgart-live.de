module LegacyRedirects
  class Report
    def call
      rows = LegacyRedirect.order(:source_path).map do |row|
        destination = Target.path_for(row)
        current = Target.resolve(row.source_path)
        result = if row.disabled?
          "disabled"
        elsif row.source_metadata["crawl_error"].present?
          "crawl_error"
        elsif current
          "current_public_200"
        elsif row.redirect? && destination
          "redirect"
        else
          "unresolved"
        end
        { source_path: row.source_path, source_kind: row.source_kind, result: result, destination: destination, origin: row.origin, reason: row.match_reason, score: row.score, crawl_error: row.source_metadata["crawl_error"] }
      end
      { generated_at: Time.current.iso8601, http_validated: false, validation: "local public-target checks only", counts: rows.group_by { |row| row[:result] }.transform_values(&:size), rows: rows }
    end

    def write(directory: Rails.root.join("tmp/legacy_redirects"))
      directory = Pathname(directory)
      directory.mkpath
      report = call
      paths = { json: directory.join("report.json"), csv: directory.join("report.csv") }
      File.write(paths[:json], JSON.pretty_generate(report))
      headers = %i[source_path source_kind result destination origin reason score crawl_error]
      File.open(paths[:csv], "w") do |csv|
        csv.write(csv_line(headers))
        report[:rows].each { |row| csv.write(csv_line(headers.map { |header| safe_csv(row[header]) })) }
      end
      paths
    end

    private

    def csv_line(values)
      values.map { |value| %Q("#{value.to_s.gsub('"', '""')}") }.join(",") + "\r\n"
    end

    def safe_csv(value)
      value.is_a?(String) && value.match?(/\A[=+@\-\t\r]/) ? "'#{value}" : value
    end
  end
end
