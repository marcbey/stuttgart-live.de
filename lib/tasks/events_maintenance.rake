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
