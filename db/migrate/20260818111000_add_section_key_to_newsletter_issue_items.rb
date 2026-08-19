class AddSectionKeyToNewsletterIssueItems < ActiveRecord::Migration[8.1]
  def change
    add_column :newsletter_issue_items, :section_key, :string
    add_index :newsletter_issue_items, [ :newsletter_issue_id, :section_key ], name: "index_newsletter_issue_items_on_issue_section"
  end
end
