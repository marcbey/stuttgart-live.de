class ImportSource < ApplicationRecord
  SOURCE_TYPES = %w[easyticket eventim reservix].freeze
  DEFAULT_EASYTICKET_LOCATION_WHITELIST = [
    "Stuttgart"
  ].freeze

  has_one :import_source_config, dependent: :destroy
  has_many :import_runs, dependent: :destroy
  has_many :easyticket_import_events, dependent: :destroy
  has_many :eventim_import_events, dependent: :destroy
  has_many :reservix_import_events, dependent: :destroy

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
    configured = import_source_config&.location_whitelist.to_a
    return configured if configured.present?
    return DEFAULT_EASYTICKET_LOCATION_WHITELIST if easyticket?

    []
  end

  private

  def self.ensure_source_with_defaults!(source_type:, name:)
    source = find_or_initialize_by(source_type: source_type)
    source.name ||= name
    source.active = true if source.active.nil?
    source.save! if source.new_record? || source.changed?

    config = source.import_source_config || source.build_import_source_config
    default_location_whitelist = default_location_whitelist_for(source_type)

    if config.location_whitelist.blank? && default_location_whitelist.present?
      config.location_whitelist = default_location_whitelist
      config.save!
    elsif config.new_record?
      config.save!
    end

    source
  end

  def self.default_location_whitelist_for(source_type)
    case source_type
    when "easyticket", "eventim", "reservix"
      DEFAULT_EASYTICKET_LOCATION_WHITELIST
    else
      []
    end
  end

  def apply_defaults
    self.active = true if active.nil?
    self.settings = {} unless settings.is_a?(Hash)
  end
end
