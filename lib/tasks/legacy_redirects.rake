namespace :legacy_redirects do
  desc "Inventory the legacy host before cutover (MAX_PAGES=10000 REFRESH=1 SOURCE_URL=https://stuttgart-live.de)"
  task inventory: :environment do
    options = { max_pages: ENV.fetch("MAX_PAGES", "10000"), refresh: ENV["REFRESH"] == "1", source_url: ENV.fetch("SOURCE_URL", LegacyRedirects::Inventory::DEFAULT_SOURCE) }
    puts JSON.pretty_generate(LegacyRedirects::Inventory.new(**options).call)
  end

  desc "Seed existing live blog source URLs and resolve all known legacy rows locally"
  task prepare: :environment do
    LegacyRedirects::Inventory.new.seed_blog_posts
    LegacyRedirect.find_each { |row| LegacyRedirects::Resolver.call(path: row.source_path, query: "") }
    puts JSON.pretty_generate(LegacyRedirects::Report.new.call.except(:rows))
  end

  desc "Write local public-target checks as JSON and CSV under tmp/legacy_redirects"
  task report: :environment do
    puts LegacyRedirects::Report.new.write.transform_values(&:to_s).to_json
  end

  desc "Measure local warm/cold resolver samples, excluding HTTP (SAMPLES=100)"
  task benchmark: :environment do
    report = LegacyRedirects::Benchmark.new(samples: ENV.fetch("SAMPLES", "100")).call
    directory = Rails.root.join("tmp/legacy_redirects")
    directory.mkpath
    File.write(directory.join("benchmark.json"), JSON.pretty_generate(report))
    puts JSON.pretty_generate(report)
  end
end
