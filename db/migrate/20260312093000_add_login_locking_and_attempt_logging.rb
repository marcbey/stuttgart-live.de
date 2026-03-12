class AddLoginLockingAndAttemptLogging < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.integer :failed_login_attempts, null: false, default: 0
      t.datetime :last_failed_login_at
      t.datetime :locked_until
    end

    add_index :users, :locked_until

    create_table :login_attempts do |t|
      t.references :user, foreign_key: true
      t.string :email_address
      t.string :ip_address
      t.string :user_agent
      t.string :outcome, null: false

      t.timestamps
    end

    add_index :login_attempts, :created_at
    add_index :login_attempts, [ :email_address, :created_at ]
    add_index :login_attempts, [ :outcome, :created_at ]
  end
end
