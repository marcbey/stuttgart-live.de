class CreateNewsletterSubscriberInterests < ActiveRecord::Migration[8.1]
  def change
    create_table :newsletter_subscriber_interests do |t|
      t.references :newsletter_subscriber, null: false, foreign_key: true, index: { name: "idx_newsletter_subscriber_interests_on_subscriber" }
      t.references :newsletter_interest, null: false, foreign_key: true, index: { name: "idx_newsletter_subscriber_interests_on_interest" }

      t.timestamps
    end

    add_index :newsletter_subscriber_interests,
              [ :newsletter_subscriber_id, :newsletter_interest_id ],
              unique: true,
              name: "idx_newsletter_subscriber_interests_on_unique_pair"
  end
end
