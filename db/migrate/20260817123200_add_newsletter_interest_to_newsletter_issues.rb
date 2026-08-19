class AddNewsletterInterestToNewsletterIssues < ActiveRecord::Migration[8.1]
  def change
    add_reference :newsletter_issues, :newsletter_interest, foreign_key: true
  end
end
