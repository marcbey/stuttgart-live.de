class CreateSocialConnectionTargets < ActiveRecord::Migration[8.1]
  def change
    create_table :social_connection_targets do |t|
      t.references :social_connection, null: false, foreign_key: true
      t.references :parent_target, foreign_key: { to_table: :social_connection_targets }
      t.string :target_type, null: false
      t.string :external_id, null: false
      t.string :name
      t.string :username
      t.text :access_token
      t.datetime :token_expires_at
      t.string :status, null: false, default: "available"
      t.boolean :selected, null: false, default: false
      t.datetime :last_synced_at
      t.text :last_error
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :social_connection_targets, [ :social_connection_id, :target_type, :external_id ],
      unique: true,
      name: "index_social_connection_targets_on_connection_and_target"
    add_index :social_connection_targets, [ :social_connection_id, :target_type, :selected ],
      name: "index_social_connection_targets_on_connection_type_selected"
    add_index :social_connection_targets, :status
  end
end
