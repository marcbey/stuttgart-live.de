class LlmGenreGroupingSnapshot < ApplicationRecord
  belongs_to :import_run
  has_one :homepage_genre_lane_configuration,
    class_name: "HomepageGenreLaneConfiguration",
    foreign_key: :snapshot_id,
    inverse_of: :snapshot,
    dependent: :destroy
  has_many :groups,
    -> { order(:position, :id) },
    class_name: "LlmGenreGroupingGroup",
    foreign_key: :snapshot_id,
    inverse_of: :snapshot,
    dependent: :destroy

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  validates :snapshot_key, presence: true, uniqueness: true
  validates :active, inclusion: { in: [ true, false ] }
  validates :active, uniqueness: { conditions: -> { where(active: true) } }, if: :active?
  validates :requested_group_count, :effective_group_count, :source_genres_count,
    numericality: { greater_than: 0, only_integer: true }
  validates :model, :prompt_template_digest, presence: true
  validate :request_payload_must_be_hash
  validate :raw_response_must_be_hash

  before_validation :assign_snapshot_key, on: :create
  before_validation :normalize_attributes

  private

  def assign_snapshot_key
    self.snapshot_key ||= SecureRandom.uuid
  end

  def normalize_attributes
    self.model = model.to_s.strip
    self.prompt_template_digest = prompt_template_digest.to_s.strip
    self.request_payload = {} unless request_payload.is_a?(Hash)
    self.raw_response = {} unless raw_response.is_a?(Hash)
  end

  def request_payload_must_be_hash
    errors.add(:request_payload, "must be a hash") unless request_payload.is_a?(Hash)
  end

  def raw_response_must_be_hash
    errors.add(:raw_response, "must be a hash") unless raw_response.is_a?(Hash)
  end
end
