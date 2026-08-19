class AddDoubleOptInToNewsletterSubscribers < ActiveRecord::Migration[8.1]
  def change
    change_table :newsletter_subscribers, bulk: true do |t|
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
    end

    add_index :newsletter_subscribers, :confirmed_at
  end
end
