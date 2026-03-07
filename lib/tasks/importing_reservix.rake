namespace :importing do
  namespace :reservix do
    desc "Run Reservix importer immediately"
    task run: :environment do
      source = ImportSource.ensure_reservix_source!
      run = Importing::Reservix::Importer.new(import_source: source).call

      puts "Reservix import finished with status=#{run.status}"
      puts "fetched=#{run.fetched_count} filtered=#{run.filtered_count} imported=#{run.imported_count} failed=#{run.failed_count}"
    end
  end
end
