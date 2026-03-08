class RemoveOrganizerNameFromImportEvents < ActiveRecord::Migration[8.1]
  def change
    remove_index :easyticket_import_events, :organizer_name if index_exists?(:easyticket_import_events, :organizer_name)
    remove_column :easyticket_import_events, :organizer_name, :string if column_exists?(:easyticket_import_events, :organizer_name)

    remove_index :eventim_import_events, :organizer_name if index_exists?(:eventim_import_events, :organizer_name)
    remove_column :eventim_import_events, :organizer_name, :string if column_exists?(:eventim_import_events, :organizer_name)

    remove_column :reservix_import_events, :organizer_name, :string if column_exists?(:reservix_import_events, :organizer_name)
  end
end
