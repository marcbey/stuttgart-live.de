class RemoveOrganizerNameFromEvents < ActiveRecord::Migration[8.1]
  def change
    remove_index :events, :organizer_name if index_exists?(:events, :organizer_name)
    remove_column :events, :organizer_name, :string
  end
end
