namespace :public_images do
  desc "Plan bounded public Event image preparation (LIMIT required; DRY_RUN defaults to true)"
  task backfill: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    records = PublicImages::Backfill.new(
      limit: ENV.fetch("LIMIT"),
      event_ids: ENV.fetch("EVENT_IDS", "").split(","),
      event_slugs: ENV.fetch("EVENT_SLUGS", "").split(","),
      dry_run:
    ).call
    puts "#{dry_run ? 'Dry-run' : 'Enqueued'}: #{records.length} records"
    records.each { |record| puts "#{record.class.name} ##{record.id}" }
  end
end
