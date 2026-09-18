class AddShowVenueDescriptionToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :show_venue_description, :boolean, default: true, null: false
  end
end
