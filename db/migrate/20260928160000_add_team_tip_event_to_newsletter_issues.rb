class AddTeamTipEventToNewsletterIssues < ActiveRecord::Migration[8.1]
  def change
    add_reference :newsletter_issues,
                  :team_tip_event,
                  foreign_key: { to_table: :events, on_delete: :nullify }
  end
end
