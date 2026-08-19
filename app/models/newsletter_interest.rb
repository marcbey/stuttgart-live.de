class NewsletterInterest < ApplicationRecord
  MAIN_GENRE_SLUGS = [
    "pop-indie-singer-songwriter",
    "rock-alternative",
    "metal-punk-hardcore",
    "hip-hop-r-n-b",
    "electronic-music-edm",
    "jazz-blues-soul",
    "klassik-oper",
    "musical-theater"
  ].freeze

  belongs_to :genre
  has_many :newsletter_subscriber_interests, dependent: :destroy
  has_many :newsletter_subscribers, through: :newsletter_subscriber_interests
  has_many :newsletter_issues, dependent: :nullify

  validates :name, :slug, :mailjet_property_name, presence: true
  validates :slug, :mailjet_property_name, uniqueness: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :normalize_attributes

  scope :publicly_selectable, -> { where(public_enabled: true).order(:position, :name) }

  def self.find_public_ids(ids)
    publicly_selectable.where(id: Array(ids).compact_blank)
  end

  private

  def normalize_attributes
    self.name = name.to_s.strip
    self.slug = slug.to_s.strip.presence || genre&.slug
    self.mailjet_property_name = mailjet_property_name.to_s.strip.presence || default_mailjet_property_name
  end

  def default_mailjet_property_name
    "interest_#{slug.to_s.tr("-", "_")}" if slug.present?
  end
end
