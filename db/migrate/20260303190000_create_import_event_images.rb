class CreateImportEventImages < ActiveRecord::Migration[8.0]
  def change
    create_table :import_event_images do |t|
      t.bigint :import_event_id, null: false
      t.string :import_class, null: false
      t.string :source, null: false
      t.string :image_type, null: false
      t.string :role, null: false, default: "gallery"
      t.string :aspect_hint, null: false, default: "unknown"
      t.integer :position, null: false, default: 0
      t.text :image_url, null: false

      t.timestamps
    end

    add_index :import_event_images, [ :import_class, :import_event_id ], name: "index_import_event_images_on_class_and_event"
    add_index :import_event_images,
      [ :import_class, :import_event_id, :source, :image_type, :image_url ],
      unique: true,
      name: "index_import_event_images_on_unique_image_per_owner"
  end
end
