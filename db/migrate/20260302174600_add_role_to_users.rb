class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :role, :string, null: false, default: "editor"
    add_column :users, :name, :string

    add_index :users, :role
  end
end
