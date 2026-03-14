namespace :events do
  namespace :maintenance do
    desc "Delete all events and event relations while keeping raw event imports"
    task purge_all: :environment do
      ActiveRecord::Base.transaction do
        EventImage.delete_all
        ImportEventImage.where(import_class: "Event").delete_all
        EventOffer.delete_all
        EventGenre.delete_all
        EventChangeLog.delete_all
        Event.delete_all
      end

      puts "Event-Daten gelöscht."
      puts "events=#{Event.count}"
      puts "event_offers=#{EventOffer.count}"
      puts "event_genres=#{EventGenre.count}"
      puts "event_change_logs=#{EventChangeLog.count}"
      puts "event_images=#{EventImage.count}"
      puts "event_import_images=#{ImportEventImage.where(import_class: 'Event').count}"
      puts "raw_event_imports=#{RawEventImport.count}"
    end
  end
end
