namespace :importing do
  namespace :easyticket do
    desc "Run Easyticket importer immediately"
    task run: :environment do
      source = ImportSource.ensure_easyticket_source!
      run = Importing::Easyticket::Importer.new(import_source: source).call

      puts "Easyticket import finished with status=#{run.status}"
      puts "fetched=#{run.fetched_count} filtered=#{run.filtered_count} imported=#{run.imported_count} failed=#{run.failed_count}"
    end
  end
end
