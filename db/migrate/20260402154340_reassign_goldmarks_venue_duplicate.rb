class ReassignGoldmarksVenueDuplicate < ActiveRecord::Migration[8.1]
  SOURCE_VENUE_ID = 19
  TARGET_VENUE_ID = 55

  class MigrationEvent < ActiveRecord::Base
    self.table_name = "events"
  end

  class MigrationVenue < ActiveRecord::Base
    self.table_name = "venues"
  end

  def up
    say_with_time("Reassigning Goldmark's events from venue #{SOURCE_VENUE_ID} to #{TARGET_VENUE_ID}") do
      next 0 unless MigrationVenue.exists?(id: SOURCE_VENUE_ID)
      next 0 unless MigrationVenue.exists?(id: TARGET_VENUE_ID)

      MigrationEvent.where(venue_id: SOURCE_VENUE_ID).update_all(
        venue_id: TARGET_VENUE_ID,
        updated_at: Time.current
      )
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot safely restore reassigned venue references"
  end
end
