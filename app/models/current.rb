class Current < ActiveSupport::CurrentAttributes
  attribute :session, :venue_match_key_index
  delegate :user, to: :session, allow_nil: true
end
