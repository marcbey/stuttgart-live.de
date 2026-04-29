namespace :importing do
  namespace :easyticket do
    desc "Run Easyticket importer immediately"
    task run: :environment do
      source = ImportSource.ensure_easyticket_source!
      run = Importing::Easyticket::Importer.new(import_source: source).call

      puts "Easyticket import finished with status=#{run.status}"
      puts "fetched=#{run.fetched_count} filtered=#{run.filtered_count} imported=#{run.imported_count} failed=#{run.failed_count}"
    end

    desc "Repair persisted Easyticket ticket URLs from raw import payload ids"
    task repair_ticket_urls: :environment do
      dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
      result = Events::Maintenance::EasyticketTicketUrlRepairer.call(dry_run: dry_run)

      puts dry_run ? "Easyticket Ticket-URLs geprüft." : "Easyticket Ticket-URLs repariert."
      puts "dry_run=#{result.dry_run}"
      puts "checked=#{result.checked_count}"
      puts "updated=#{result.updated_count}"
      puts "unchanged=#{result.unchanged_count}"
      puts "missing_raw_import=#{result.missing_raw_import_count}"
      puts "blank_expected_url=#{result.blank_expected_url_count}"
    end
  end
end
