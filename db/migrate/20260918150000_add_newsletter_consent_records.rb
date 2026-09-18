class AddNewsletterConsentRecords < ActiveRecord::Migration[8.1]
  def change
    change_table :newsletter_subscribers, bulk: true do |t|
      t.datetime :newsletter_consent_at
      t.string :consent_version
      t.string :confirmation_nonce
      t.boolean :requested_tracking_consent, default: false, null: false
      t.boolean :open_tracking_consent, default: false, null: false
      t.boolean :click_tracking_consent, default: false, null: false
    end

    create_table :newsletter_consent_events do |t|
      t.references :newsletter_subscriber, null: false, foreign_key: true
      t.string :email, null: false
      t.string :action, null: false
      t.string :source, null: false
      t.string :consent_version, null: false
      t.jsonb :consent_text, null: false, default: {}
      t.boolean :open_tracking_consent, null: false, default: false
      t.boolean :click_tracking_consent, null: false, default: false
      t.datetime :occurred_at, null: false
    end
  end
end
