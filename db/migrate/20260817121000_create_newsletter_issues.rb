class CreateNewsletterIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :newsletter_issues do |t|
      t.string :title, null: false
      t.string :subject, null: false
      t.string :preheader
      t.text :intro
      t.string :status, null: false, default: "draft"
      t.bigint :mailjet_campaign_draft_id
      t.bigint :mailjet_campaign_id
      t.text :mailjet_error_message
      t.datetime :mailjet_last_synced_at
      t.datetime :test_sent_at
      t.datetime :sent_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :sent_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :newsletter_issues, :status
    add_index :newsletter_issues, :mailjet_campaign_draft_id
  end
end
