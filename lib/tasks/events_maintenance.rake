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

    desc "Reset published_at for all events"
    task reset_published_at: :environment do
      relation = Event.where.not(published_at: nil)
      updated_count = relation.count
      relation.update_all(published_at: nil, updated_at: Time.current)

      puts "Event-Veröffentlichungsdaten zurückgesetzt."
      puts "events_updated=#{updated_count}"
    end

    desc "Enqueue cache warming jobs for imported event images"
    task warm_import_image_cache: :environment do
      result = Events::Maintenance::ImportImageCacheWarmer.call(
        scope: ENV.fetch("SCOPE", "published"),
        include_failed: ENV.fetch("INCLUDE_FAILED", false),
        limit: ENV["LIMIT"]
      )

      print_events_import_image_cache_warming_result(
        result,
        success_message: "Importbild-Cache-Warming enqueued."
      )
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

def print_events_import_image_cache_warming_result(result, success_message:)
  puts success_message
  puts "images_scanned=#{result.images_scanned}"
  puts "images_eligible=#{result.images_eligible}"
  puts "jobs_enqueued=#{result.jobs_enqueued}"
  puts "images_skipped_cached=#{result.images_skipped_cached}"
  puts "images_skipped_invalid=#{result.images_skipped_invalid}"
  puts "images_skipped_failed=#{result.images_skipped_failed}"
end
