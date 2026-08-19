class AddTeamTipToNewsletterIssues < ActiveRecord::Migration[8.1]
  def change
    change_table :newsletter_issues, bulk: true do |t|
      t.string :team_tip_profile_key
      t.string :team_tip_name
      t.string :team_tip_role
      t.string :team_tip_image_url
      t.text :team_tip_text
    end
  end
end
