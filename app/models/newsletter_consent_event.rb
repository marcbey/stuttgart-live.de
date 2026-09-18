class NewsletterConsentEvent < ApplicationRecord
  belongs_to :newsletter_subscriber

  validates :email, :action, :source, :consent_version, :consent_text, :occurred_at, presence: true

  def readonly?
    persisted?
  end
end
