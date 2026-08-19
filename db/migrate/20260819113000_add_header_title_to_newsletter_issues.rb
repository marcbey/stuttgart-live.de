class AddHeaderTitleToNewsletterIssues < ActiveRecord::Migration[8.1]
  def change
    add_column :newsletter_issues, :header_title, :string
    add_column :newsletter_issues, :jump_menu_title, :string
  end
end
