class ImportSource < ApplicationRecord
  SOURCE_TYPES = %w[easyticket eventim reservix].freeze

  has_one :import_source_config, dependent: :destroy
  has_many :import_runs, dependent: :destroy
  has_many :raw_event_imports, dependent: :destroy

  validates :name, presence: true
  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }, uniqueness: true
  validates :active, inclusion: { in: [ true, false ] }

  before_validation :apply_defaults

  def self.ensure_easyticket_source!
    ensure_source_with_defaults!(source_type: "easyticket", name: "Easyticket")
  end

  def self.ensure_eventim_source!
    ensure_source_with_defaults!(source_type: "eventim", name: "Eventim")
  end

  def self.ensure_reservix_source!
    ensure_source_with_defaults!(source_type: "reservix", name: "Reservix")
  end

  def self.ensure_supported_sources!
    ensure_easyticket_source!
    ensure_eventim_source!
    ensure_reservix_source!
  end

  def easyticket?
    source_type == "easyticket"
  end

  def eventim?
    source_type == "eventim"
  end

  def reservix?
    source_type == "reservix"
  end

  def configured_location_whitelist
    import_source_config&.location_whitelist.to_a
  end

  private

  def self.ensure_source_with_defaults!(source_type:, name:)
    source = find_or_initialize_by(source_type: source_type)
    source.name ||= name
    source.active = true if source.active.nil?
    source.save! if source.new_record? || source.changed?

    config = source.import_source_config || source.build_import_source_config
    config.save! if config.new_record?

    source
  end

  def apply_defaults
    self.active = true if active.nil?
    self.settings = {} unless settings.is_a?(Hash)
  end
end
