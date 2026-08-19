class NewsletterIssue < ApplicationRecord
  STATUSES = %w[draft synced tested sending sent failed].freeze
  LAYOUT_VARIANTS = %w[standard genre_weekly_mix].freeze

  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :sent_by, class_name: "User", optional: true
  belongs_to :newsletter_interest, optional: true
  has_many :newsletter_issue_items, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :newsletter_issue
  has_many :events, through: :newsletter_issue_items, source: :item, source_type: "Event"
  has_many :blog_posts, through: :newsletter_issue_items, source: :item, source_type: "BlogPost"

  accepts_nested_attributes_for :newsletter_issue_items, allow_destroy: true

  validates :title, :subject, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :layout_variant, inclusion: { in: LAYOUT_VARIANTS }
  validates :header_title, length: { maximum: 120 }, allow_blank: true
  validates :jump_menu_title, length: { maximum: 140 }, allow_blank: true
  validates :preheader, length: { maximum: 180 }, allow_blank: true
  validates :team_tip_image_url, format: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true

  before_validation :normalize_attributes
  before_validation :apply_team_tip_profile

  scope :ordered_for_backend, -> { includes(:created_by).order(updated_at: :desc, id: :desc) }

  def draft?
    status == "draft"
  end

  def sent?
    status == "sent"
  end

  def genre_weekly_mix?
    layout_variant == "genre_weekly_mix"
  end

  def team_tip?
    team_tip_name.present? && team_tip_text.present?
  end

  def team_tip_initials
    team_tip_name.to_s.split.map { |part| part.first.to_s.upcase }.join.first(2)
  end

  def display_header_title
    subject
  end

  def display_jump_menu_title
    jump_menu_title.presence || "Für was interessierst du dich? Spring hinein ins Vergnügen :-)"
  end

  def grouped_items_for_backend
    return [ { label: nil, items: newsletter_issue_items.to_a } ] unless genre_weekly_mix?

    all_items = newsletter_issue_items.includes(:item).to_a
    news_items = all_items.select { |item| item.item.is_a?(BlogPost) }
    grouped_items = (all_items - news_items).group_by(&:effective_section_key)
    groups = []
    groups << { label: "News", items: sort_weekly_mix_news_items(news_items) } if news_items.any?

    groups.concat(
      Newsletter::HeaderGenreGroups.all.filter_map do |group|
        items = grouped_items.delete(group.slug)
        next if items.blank?

        { label: group.label, items: sort_weekly_mix_items(items) }
      end
    )
    leftover_items = sort_weekly_mix_items(grouped_items.values.flatten)

    groups << { label: "Weitere Inhalte", items: leftover_items } if leftover_items.any?
    groups
  end

  def sort_items_by_date!
    newsletter_issue_items
      .includes(:item)
      .sort_by { |item| [ item.sort_date ? -item.sort_date.to_i : Float::INFINITY, item.id ] }
      .each.with_index(1) { |item, position| item.update!(position:) }
  end

  def sort_weekly_mix_positions!
    return unless genre_weekly_mix?

    grouped_items_for_backend
      .flat_map { |group| group.fetch(:items) }
      .each.with_index(1) { |item, position| item.update!(position:) }
  end

  def sort_weekly_mix_items(items)
    deduplicate_weekly_mix_series(items)
      .sort_by { |item| [ item.sort_date || Time.zone.local(9999, 12, 31), item.id ] }
  end

  def sort_weekly_mix_news_items(items)
    items.sort_by { |item| [ item.sort_date ? -item.sort_date.to_i : Float::INFINITY, item.id ] }
  end

  def deduplicate_weekly_mix_series(items)
    items
      .group_by { |item| weekly_mix_series_key_for(item) }
      .values
      .map { |group| group.min_by { |item| [ item.sort_date || Time.zone.local(9999, 12, 31), item.id ] } }
  end

  def weekly_mix_series_key_for(item)
    return "item-#{item.id}" unless item.item.is_a?(Event)

    item.item.event_series_id.presence || "event-#{item.item.id}"
  end

  def mark_mailjet_synced!(draft_id:)
    update!(
      mailjet_campaign_draft_id: draft_id,
      mailjet_last_synced_at: Time.current,
      mailjet_error_message: nil,
      status: "synced"
    )
  end

  def mark_test_sent!
    update!(
      test_sent_at: Time.current,
      mailjet_error_message: nil,
      status: "tested"
    )
  end

  def mark_mailjet_failed!(message)
    update!(
      mailjet_error_message: message.to_s.truncate(1_000),
      status: "failed"
    )
  end

  private

  def normalize_attributes
    self.title = title.to_s.strip
    self.subject = subject.to_s.strip
    self.header_title = header_title.to_s.strip.presence
    self.jump_menu_title = jump_menu_title.to_s.strip.presence
    self.layout_variant = layout_variant.to_s.strip.presence || "standard"
    self.preheader = preheader.to_s.strip.presence
    self.intro = intro.to_s.strip.presence
    self.team_tip_profile_key = team_tip_profile_key.to_s.strip.presence
    self.team_tip_name = team_tip_name.to_s.strip.presence
    self.team_tip_role = team_tip_role.to_s.strip.presence
    self.team_tip_image_url = team_tip_image_url.to_s.strip.presence
    self.team_tip_text = team_tip_text.to_s.strip.presence
  end

  def apply_team_tip_profile
    profile = Newsletter::TeamTipProfiles.find(team_tip_profile_key)
    return if profile.blank?

    self.team_tip_name = profile.name if team_tip_name.blank?
    self.team_tip_role = profile.role if team_tip_role.blank?
  end
end
