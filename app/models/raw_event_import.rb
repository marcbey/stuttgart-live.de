class RawEventImport < ApplicationRecord
  belongs_to :import_source

  validates :import_event_type, presence: true, inclusion: { in: ImportSource::SOURCE_TYPES }
  validates :source_identifier, presence: true
  validate :payload_must_be_hash
  validate :detail_payload_must_be_hash

  before_validation :normalize_attributes

  scope :chronological, -> { order(created_at: :asc, id: :asc) }

  def self.latest_for(relation = all)
    latest_rows =
      relation
        .select(latest_for_select_sql)
        .reorder(Arel.sql(latest_for_order_sql))

    from(latest_rows, table_name).chronological
  end

  private

  def self.latest_for_select_sql
    sanitize_sql_array([
      "DISTINCT ON (%s.import_event_type, %s.source_identifier) %s.*",
      quoted_table_name,
      quoted_table_name,
      quoted_table_name
    ])
  end

  def self.latest_for_order_sql
    [
      "#{quoted_table_name}.import_event_type ASC",
      "#{quoted_table_name}.source_identifier ASC",
      "#{quoted_table_name}.created_at DESC",
      "#{quoted_table_name}.id DESC"
    ].join(", ")
  end

  private_class_method :latest_for_select_sql, :latest_for_order_sql

  def normalize_attributes
    self.import_event_type = import_event_type.to_s.strip
    self.source_identifier = source_identifier.to_s.strip
    self.payload = {} unless payload.is_a?(Hash)
    self.detail_payload = {} unless detail_payload.is_a?(Hash)
  end

  def payload_must_be_hash
    errors.add(:payload, "must be a hash") unless payload.is_a?(Hash)
  end

  def detail_payload_must_be_hash
    errors.add(:detail_payload, "must be a hash") unless detail_payload.is_a?(Hash)
  end
end
