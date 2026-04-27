class SplitMetaSocialConnectionsByPlatform < ActiveRecord::Migration[8.1]
  def up
    add_column :social_connections, :platform, :string

    execute <<~SQL.squish
      UPDATE social_connections
      SET platform = CASE
        WHEN auth_mode = 'facebook_login_for_business' THEN 'facebook'
        ELSE 'instagram'
      END
      WHERE platform IS NULL
    SQL

    change_column_null :social_connections, :platform, false
    remove_index :social_connections, :provider
    add_index :social_connections, [ :provider, :platform ], unique: true
  end

  def down
    remove_index :social_connections, [ :provider, :platform ]
    add_index :social_connections, :provider, unique: true
    remove_column :social_connections, :platform
  end
end
