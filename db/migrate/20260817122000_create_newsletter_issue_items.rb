class CreateNewsletterIssueItems < ActiveRecord::Migration[8.1]
  def change
    create_table :newsletter_issue_items do |t|
      t.references :newsletter_issue, null: false, foreign_key: true
      t.references :item, null: false, polymorphic: true
      t.integer :position, null: false, default: 0
      t.string :headline_override
      t.text :teaser_override
      t.string :cta_label

      t.timestamps
    end

    add_index :newsletter_issue_items, [ :newsletter_issue_id, :position, :id ], name: "index_newsletter_issue_items_on_issue_position"
    add_index :newsletter_issue_items, [ :newsletter_issue_id, :item_type, :item_id ], unique: true, name: "index_newsletter_issue_items_on_unique_item"
  end
end
