class CreateEventImages < ActiveRecord::Migration[8.1]
  def change
    create_table :event_images do |t|
      t.references :event, null: false, foreign_key: true
      t.string :purpose, null: false
      t.string :grid_variant
      t.string :alt_text
      t.text :sub_text

      t.timestamps
    end

    add_index :event_images, [ :event_id, :purpose ]
    add_index :event_images, [ :event_id, :purpose ],
      unique: true,
      where: "purpose = 'detail_hero'",
      name: "index_event_images_on_unique_detail_hero_per_event"
    add_index :event_images, [ :event_id, :grid_variant ],
      unique: true,
      where: "purpose = 'grid_tile'",
      name: "index_event_images_on_unique_grid_variant_per_event"
  end
end
