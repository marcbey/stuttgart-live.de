namespace :venues do
  namespace :maintenance do
    desc "Merge duplicate venues based on flexible venue matching"
    task backfill_duplicates: :environment do
      result = Venues::Maintenance::Deduplicator.call
      print_venues_maintenance_result(result, success_message: "Venue-Dubletten bereinigt.")
    end
  end
end

def print_venues_maintenance_result(result, success_message:)
  puts success_message
  puts "groups=#{result.groups}"
  puts "venues_merged=#{result.venues_merged}"
  puts "events_reassigned=#{result.events_reassigned}"
  puts "venues_deleted=#{result.venues_deleted}"
end
