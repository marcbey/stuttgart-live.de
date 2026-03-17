class AddReservixHomepageIndexToEvents < ActiveRecord::Migration[8.1]
  def change
    add_index :events, [ :start_at, :id ],
      name: "index_events_on_published_reservix_start_at_and_id",
      where: "status = 'published' AND primary_source = 'reservix'"
  end
end
