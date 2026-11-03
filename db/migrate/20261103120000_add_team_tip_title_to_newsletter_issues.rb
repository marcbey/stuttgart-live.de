class AddTeamTipTitleToNewsletterIssues < ActiveRecord::Migration[8.1]
  def change
    add_column :newsletter_issues, :team_tip_title, :string
  end
end
