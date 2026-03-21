class CreatePresenters < ActiveRecord::Migration[8.1]
  def change
    create_table :presenters do |t|
      t.string :name, null: false
      t.text :description
      t.string :external_url, null: false

      t.timestamps
    end

    create_table :event_presenters do |t|
      t.references :event, null: false, foreign_key: true
      t.references :presenter, null: false, foreign_key: true
      t.integer :position, null: false

      t.timestamps
    end

    add_index :presenters, :name
    add_index :event_presenters, [ :event_id, :presenter_id ], unique: true
    add_index :event_presenters, [ :event_id, :position ], unique: true
  end
end
