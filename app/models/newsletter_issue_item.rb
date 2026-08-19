class NewsletterIssueItem < ApplicationRecord
  ALLOWED_ITEM_TYPES = %w[Event BlogPost].freeze

  belongs_to :newsletter_issue, inverse_of: :newsletter_issue_items
  belongs_to :item, polymorphic: true

  validates :item_type, inclusion: { in: ALLOWED_ITEM_TYPES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :item_id, uniqueness: { scope: [ :newsletter_issue_id, :item_type ] }
  validate :section_key_must_match_header_genre_for_weekly_mix

  before_validation :normalize_attributes

  def display_headline
    headline_override.presence || default_headline
  end

  def display_teaser
    teaser_override.presence || default_teaser
  end

  def display_cta_label
    cta_label.presence || default_cta_label
  end

  def display_kind
    item.is_a?(Event) ? "Event" : "News"
  end

  def display_date
    return item.start_at if item.is_a?(Event)

    item.published_at
  end

  def sort_date
    display_date
  end

  def effective_section_key
    section_key.presence || inferred_section_key
  end

  private

  def normalize_attributes
    self.headline_override = headline_override.to_s.strip.presence
    self.teaser_override = teaser_override.to_s.strip.presence
    self.cta_label = cta_label.to_s.strip.presence
    self.section_key = section_key.to_s.strip.presence
  end

  def default_headline
    return item.artist_name if item.is_a?(Event)

    item.title
  end

  def default_teaser
    return event_teaser if item.is_a?(Event)

    item.teaser
  end

  def event_teaser
    item.title
  end

  def default_cta_label
    item.is_a?(Event) ? "Zum Event" : "Zur News"
  end

  def inferred_section_key
    return unless item.is_a?(Event)

    event_genre_slugs = item.genres.map(&:slug)
    Newsletter::HeaderGenreGroups.all.find { |group| event_genre_slugs.include?(group.slug) }&.slug
  end

  def section_key_must_match_header_genre_for_weekly_mix
    return unless newsletter_issue&.genre_weekly_mix?
    return unless item.is_a?(Event)

    if section_key.blank?
      errors.add(:section_key, "muss ausgewählt werden")
    elsif Newsletter::HeaderGenreGroups.all.none? { |group| group.slug == section_key }
      errors.add(:section_key, "ist kein Wochenmix-Genre")
    end
  end
end
