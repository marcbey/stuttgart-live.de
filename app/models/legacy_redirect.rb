class LegacyRedirect < ApplicationRecord
  SOURCE_KINDS = %w[event news page genre file].freeze
  STATUSES = %w[unresolved redirect disabled].freeze
  ORIGINS = %w[automatic manual].freeze

  belongs_to :target, polymorphic: true, optional: true
  attr_reader :destination_input

  before_validation :normalize_source_path
  before_validation :normalize_target_path
  validates :source_path, presence: true, uniqueness: true
  validates :source_kind, inclusion: { in: SOURCE_KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :origin, inclusion: { in: ORIGINS }
  validate :valid_source_path
  validate :valid_destination, if: :redirect?

  def manual?
    origin == "manual"
  end

  def redirect?
    status == "redirect"
  end

  def disabled?
    status == "disabled"
  end

  def destination=(value)
    @destination_input = value
    resolved = LegacyRedirects::Target.resolve(value)
    self.target = resolved&.fetch(:target)
    self.target_path = resolved&.fetch(:target_path)
  end

  def destination
    LegacyRedirects::Target.path_for(self)
  end

  private

  def normalize_source_path
    normalized = LegacyRedirects::SourceKey.normalize(source_path)
    self.source_path = normalized if normalized
  end

  def normalize_target_path
    return if target_path.blank?

    normalized = LegacyRedirects::Target.resolve(target_path)&.fetch(:target_path)
    self.target_path = normalized if normalized
  end

  def valid_source_path
    errors.add(:source_path, "ist keine gültige öffentliche Quelladresse") unless LegacyRedirects::SourceKey.normalize(source_path)
  end

  def valid_destination
    path = destination
    return errors.add(:destination, "muss ein gültiges öffentliches Ziel sein") if path.blank?
    return errors.add(:destination, "darf nicht mit der Quelle übereinstimmen") if path == source_path

    if self.class.where.not(id: id).where(source_path: path, status: "redirect").exists?
      errors.add(:destination, "darf keine weitere Weiterleitung sein")
    end
    incoming = self.class.where.not(id: id).where(status: "redirect")
    sources = incoming.where(target_path: source_path)
    source_target = LegacyRedirects::Target.resolve(source_path)&.fetch(:target)
    sources = sources.or(incoming.where(target_type: source_target.class.name, target_id: source_target.id)) if source_target
    if sources.exists?
      errors.add(:source_path, "darf keine Weiterleitungskette erzeugen")
    end
  end
end
