class NewsletterSubscriberInterest < ApplicationRecord
  belongs_to :newsletter_subscriber
  belongs_to :newsletter_interest

  validates :newsletter_interest_id, uniqueness: { scope: :newsletter_subscriber_id }
end
