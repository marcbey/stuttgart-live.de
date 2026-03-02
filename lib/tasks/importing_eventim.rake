namespace :importing do
  namespace :eventim do
    desc "Run Eventim importer immediately"
    task run: :environment do
      source = ImportSource.ensure_eventim_source!
      run = Importing::Eventim::Importer.new(import_source: source).call

      puts "Eventim import finished with status=#{run.status}"
      puts "fetched=#{run.fetched_count} filtered=#{run.filtered_count} imported=#{run.imported_count} failed=#{run.failed_count}"
    end
  end
end
