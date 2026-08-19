class AddLayoutVariantToNewsletterIssues < ActiveRecord::Migration[8.1]
  def change
    add_column :newsletter_issues, :layout_variant, :string, null: false, default: "standard"
    add_index :newsletter_issues, :layout_variant
  end
end
