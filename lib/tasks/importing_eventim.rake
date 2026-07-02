namespace :importing do
  namespace :eventim do
    desc "Run Eventim importer immediately"
    task run: :environment do
      source = ImportSource.ensure_eventim_source!
      run = Importing::Eventim::Importer.new(import_source: source).call

      puts "Eventim import finished with status=#{run.status}"
      puts "fetched=#{run.fetched_count} filtered=#{run.filtered_count} imported=#{run.imported_count} failed=#{run.failed_count}"
    end

    desc "Repair persisted Eventim ticket offers from current raw imports"
    task repair_ticket_offers: :environment do
      dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
      result = Events::Maintenance::EventimTicketOfferRepairer.call(dry_run: dry_run)

      puts dry_run ? "Eventim Ticket-Angebote geprüft." : "Eventim Ticket-Angebote repariert."
      puts "dry_run=#{result.dry_run}"
      puts "checked_events=#{result.checked_events}"
      puts "updated_events=#{result.updated_events}"
      puts "created_offers=#{result.created_offers}"
      puts "removed_stale_offers=#{result.removed_stale_offers}"
      puts "ignored_auxiliary_records=#{result.ignored_auxiliary_records}"
      puts "ambiguous_events=#{result.ambiguous_events}"

      result.series_summaries.sort.each do |series_name, summary|
        puts [
          "series=#{series_name}",
          "checked_events=#{summary.fetch("checked_events")}",
          "updated_events=#{summary.fetch("updated_events")}",
          "removed_stale_offers=#{summary.fetch("removed_stale_offers")}",
          "ambiguous_events=#{summary.fetch("ambiguous_events")}",
          "created_offers=#{summary.fetch("created_offers")}",
          "ignored_auxiliary_records=#{summary.fetch("ignored_auxiliary_records")}"
        ].join(" ")
      end
    end
  end
end
