class DeleteGoldmarksSourceVenue < ActiveRecord::Migration[8.1]
  SOURCE_VENUE_ID = 19

  class MigrationEvent < ActiveRecord::Base
    self.table_name = "events"
  end

  class MigrationVenue < ActiveRecord::Base
    self.table_name = "venues"
  end

  def up
    say_with_time("Deleting duplicate Goldmark's venue #{SOURCE_VENUE_ID}") do
      next 0 unless MigrationVenue.exists?(id: SOURCE_VENUE_ID)

      remaining_events = MigrationEvent.where(venue_id: SOURCE_VENUE_ID).count
      raise ActiveRecord::IrreversibleMigration, "Venue #{SOURCE_VENUE_ID} still has #{remaining_events} events" if remaining_events.positive?

      MigrationVenue.where(id: SOURCE_VENUE_ID).delete_all
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot safely restore a deleted duplicate venue"
  end
end
