class CreatePublishAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :publish_attempts do |t|
      t.references :event_social_post, null: false, foreign_key: true
      t.references :social_connection, foreign_key: true
      t.references :social_connection_target, foreign_key: true
      t.references :initiated_by, foreign_key: { to_table: :users }
      t.string :platform, null: false
      t.string :status, null: false, default: "started"
      t.string :error_code
      t.text :error_message
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.jsonb :request_snapshot, null: false, default: {}
      t.jsonb :response_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :publish_attempts, :platform
    add_index :publish_attempts, :status
    add_index :publish_attempts, [ :event_social_post_id, :created_at ]
  end
end
