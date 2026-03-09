class NewsletterSubscriber < ApplicationRecord
  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { case_sensitive: false }
  validates :source, presence: true

  before_validation :normalize_email

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
    self.source = source.to_s.strip.presence || "homepage"
  end
end
