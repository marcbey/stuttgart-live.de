class AddShowOrganizerNotesToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :show_organizer_notes, :boolean, default: false, null: false
  end
end
