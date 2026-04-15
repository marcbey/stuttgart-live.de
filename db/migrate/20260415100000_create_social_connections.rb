class CreateSocialConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :social_connections do |t|
      t.string :provider, null: false
      t.string :auth_mode, null: false
      t.string :connection_status, null: false, default: "disconnected"
      t.string :external_user_id
      t.text :user_access_token
      t.datetime :user_token_expires_at
      t.jsonb :granted_scopes, null: false, default: []
      t.datetime :connected_at
      t.datetime :last_token_check_at
      t.datetime :last_refresh_at
      t.datetime :reauth_required_at
      t.text :last_error
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :social_connections, :provider, unique: true
    add_index :social_connections, :connection_status
  end
end
