class RenameNewsletterSubscriberExternalSyncFields < ActiveRecord::Migration[8.1]
  def up
    rename_column :newsletter_subscribers, :mailchimp_status, :external_sync_status
    rename_column :newsletter_subscribers, :mailchimp_member_id, :external_contact_id
    rename_column :newsletter_subscribers, :mailchimp_last_synced_at, :external_last_synced_at
    rename_column :newsletter_subscribers, :mailchimp_error_message, :external_error_message
    add_column :newsletter_subscribers, :external_sync_provider, :string

    rename_index_if_exists(
      :newsletter_subscribers,
      "index_newsletter_subscribers_on_mailchimp_status",
      "index_newsletter_subscribers_on_external_sync_status"
    )
    rename_index_if_exists(
      :newsletter_subscribers,
      "index_newsletter_subscribers_on_mailchimp_member_id",
      "index_newsletter_subscribers_on_external_contact_id"
    )
  end

  def down
    rename_index_if_exists(
      :newsletter_subscribers,
      "index_newsletter_subscribers_on_external_sync_status",
      "index_newsletter_subscribers_on_mailchimp_status"
    )
    rename_index_if_exists(
      :newsletter_subscribers,
      "index_newsletter_subscribers_on_external_contact_id",
      "index_newsletter_subscribers_on_mailchimp_member_id"
    )

    remove_column :newsletter_subscribers, :external_sync_provider
    rename_column :newsletter_subscribers, :external_error_message, :mailchimp_error_message
    rename_column :newsletter_subscribers, :external_last_synced_at, :mailchimp_last_synced_at
    rename_column :newsletter_subscribers, :external_contact_id, :mailchimp_member_id
    rename_column :newsletter_subscribers, :external_sync_status, :mailchimp_status
  end

  private

  def rename_index_if_exists(table_name, old_name, new_name)
    rename_index table_name, old_name, new_name if index_name_exists?(table_name, old_name)
  end
end
