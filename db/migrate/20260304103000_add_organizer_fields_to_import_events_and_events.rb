class AddOrganizerFieldsToImportEventsAndEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :easyticket_import_events, :organizer_name, :string
    add_column :easyticket_import_events, :organizer_id, :string
    add_index :easyticket_import_events, :organizer_name
    add_index :easyticket_import_events, :organizer_id

    add_column :eventim_import_events, :promoter_id, :string
    add_column :eventim_import_events, :organizer_name, :string
    add_index :eventim_import_events, :promoter_id
    add_index :eventim_import_events, :organizer_name

    add_column :events, :organizer_name, :string
    add_column :events, :promoter_id, :string
    add_index :events, :organizer_name
    add_index :events, :promoter_id
  end
end
