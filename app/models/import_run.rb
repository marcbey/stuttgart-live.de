class ImportRun < ApplicationRecord
  STATUSES = %w[queued running succeeded failed canceled].freeze

  belongs_to :import_source
  has_many :import_run_errors, dependent: :destroy
  has_one :llm_genre_grouping_snapshot, dependent: :destroy

  validates :source_type, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :started_at, presence: true
  validates :fetched_count, :filtered_count, :imported_count, :upserted_count, :failed_count,
    numericality: { greater_than_or_equal_to: 0, only_integer: true }

  before_validation :apply_defaults
  before_validation :sync_source_type_from_import_source

  scope :recent, -> { order(created_at: :desc) }

  private

  def apply_defaults
    self.status ||= "running"
    self.started_at ||= Time.current
    self.fetched_count ||= 0
    self.filtered_count ||= 0
    self.imported_count ||= 0
    self.upserted_count ||= 0
    self.failed_count ||= 0
    self.metadata = {} unless metadata.is_a?(Hash)
  end

  def sync_source_type_from_import_source
    self.source_type = import_source&.source_type if source_type.blank?
  end
end
