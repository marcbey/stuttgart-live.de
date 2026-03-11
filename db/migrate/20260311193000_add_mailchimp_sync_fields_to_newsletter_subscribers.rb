class AddMailchimpSyncFieldsToNewsletterSubscribers < ActiveRecord::Migration[8.1]
  def change
    change_table :newsletter_subscribers, bulk: true do |t|
      t.string :mailchimp_status, null: false, default: "pending"
      t.string :mailchimp_member_id
      t.datetime :mailchimp_last_synced_at
      t.text :mailchimp_error_message
    end

    add_index :newsletter_subscribers, :mailchimp_status
    add_index :newsletter_subscribers, :mailchimp_member_id
  end
end
