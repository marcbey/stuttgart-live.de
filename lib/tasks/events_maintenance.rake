namespace :events do
  namespace :maintenance do
    desc "Delete all events and event relations while keeping raw event imports"
    task purge_all: :environment do
      result = Events::Maintenance::Purger.call
      print_events_maintenance_result(result, success_message: "Event-Daten gelöscht.")
    end

    desc "Delete all events, import runtime data, and Solid Queue jobs while keeping importer setup"
    task purge_all_with_imports: :environment do
      result = Events::Maintenance::Purger.call(include_imports: true, include_solid_queue: true)
      print_events_maintenance_result(result, success_message: "Event-, Import- und Queue-Daten gelöscht.")
    end

    desc "Reset all event LLM enrichments, related LLM runs, and queued LLM jobs"
    task reset_llm_enrichment: :environment do
      result = Events::Maintenance::LlmResetter.call
      print_events_llm_maintenance_result(result, success_message: "LLM-Enrichment-Daten zurückgesetzt.")
    end

    desc "Enqueue a chunked LLM link refresh backfill for future events with existing enrichments"
    task backfill_llm_links: :environment do
      chunk_size = ENV.fetch("CHUNK_SIZE", Events::Maintenance::LlmLinkBackfillEnqueuer::DEFAULT_CHUNK_SIZE)
      statuses = ENV.fetch("STATUSES", Events::Maintenance::LlmLinkBackfillEnqueuer::DEFAULT_STATUSES.join(",")).split(",")

      result = Events::Maintenance::LlmLinkBackfillEnqueuer.call(chunk_size:, statuses:)
      puts "LLM-Link-Backfill eingereiht."
      puts "eligible_events=#{result.eligible_count}"
      puts "runs_enqueued=#{result.runs_enqueued}"
      puts "chunk_size=#{result.chunk_size}"
      puts "statuses=#{result.statuses.join(',')}"
    end

    desc "Reset published_at for all events"
    task reset_published_at: :environment do
      relation = Event.where.not(published_at: nil)
      updated_count = relation.count
      relation.update_all(published_at: nil, updated_at: Time.current)

      puts "Event-Veröffentlichungsdaten zurückgesetzt."
      puts "events_updated=#{updated_count}"
    end
  end
end

def print_events_maintenance_result(result, success_message:)
  puts success_message

  result.event_counts.each do |name, count|
    puts "#{name}=#{count}"
  end

  result.import_counts.each do |name, count|
    puts "#{name}=#{count}"
  end

  case result.solid_queue_status
  when :cleared
    result.solid_queue_counts.each do |name, count|
      puts "#{name}=#{count}"
    end
  when :skipped
    puts "solid_queue=übersprungen"
  end
end

def print_events_llm_maintenance_result(result, success_message:)
  puts success_message

  result.event_counts.each do |name, count|
    puts "#{name}=#{count}"
  end

  result.import_counts.each do |name, count|
    puts "#{name}=#{count}"
  end

  case result.queue_status
  when :cleared
    result.queue_counts.each do |name, count|
      puts "#{name}=#{count}"
    end
  when :skipped
    puts "solid_queue=übersprungen"
  end
end
