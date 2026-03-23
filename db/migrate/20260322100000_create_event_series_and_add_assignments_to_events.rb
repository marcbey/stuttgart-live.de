class CreateEventSeriesAndAddAssignmentsToEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :event_series do |t|
      t.string :name
      t.string :origin, null: false
      t.string :source_type
      t.string :source_key

      t.timestamps
    end

    add_index :event_series, [ :source_type, :source_key ],
      unique: true,
      where: "source_key IS NOT NULL",
      name: "index_event_series_on_source_type_and_source_key"

    add_reference :events, :event_series, foreign_key: true
    add_column :events, :event_series_assignment, :string, null: false, default: "auto"
    add_index :events, :event_series_assignment
  end
end
