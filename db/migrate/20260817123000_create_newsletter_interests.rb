class CreateNewsletterInterests < ActiveRecord::Migration[8.1]
  MAIN_GENRE_SLUGS = [
    "pop-indie-singer-songwriter",
    "rock-alternative",
    "metal-punk-hardcore",
    "hip-hop-r-n-b",
    "electronic-music-edm",
    "jazz-blues-soul",
    "klassik-oper",
    "musical-theater"
  ].freeze

  def change
    create_table :newsletter_interests do |t|
      t.references :genre, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :mailjet_property_name, null: false
      t.bigint :mailjet_segment_id
      t.integer :position, null: false, default: 0
      t.boolean :public_enabled, null: false, default: true

      t.timestamps
    end

    add_index :newsletter_interests, :slug, unique: true
    add_index :newsletter_interests, :mailjet_property_name, unique: true
    add_index :newsletter_interests, :mailjet_segment_id
    add_index :newsletter_interests, [ :public_enabled, :position ]
  end
end
