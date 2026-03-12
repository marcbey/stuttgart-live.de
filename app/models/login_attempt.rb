class LoginAttempt < ApplicationRecord
  OUTCOMES = %w[successful failed locked].freeze

  belongs_to :user, optional: true

  normalizes :email_address, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :outcome, inclusion: { in: OUTCOMES }

  scope :recent_first, -> { order(created_at: :desc) }
end
