class CreateNewsletterSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :newsletter_subscribers do |t|
      t.string :email, null: false
      t.string :source, null: false, default: "homepage"

      t.timestamps
    end

    add_index :newsletter_subscribers, "lower(email)", unique: true, name: "index_newsletter_subscribers_on_lower_email"
  end
end
