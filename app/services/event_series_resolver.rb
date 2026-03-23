class EventSeriesResolver
  class << self
    def ensure_imported!(reference)
      normalized_reference = normalize_reference(reference)
      return if normalized_reference.nil?

      series = EventSeries.find_or_initialize_by(
        source_type: normalized_reference.source_type,
        source_key: normalized_reference.source_key
      )
      series.origin = "imported"
      series.name = normalized_reference.name if normalized_reference.name.present?
      series.save! if series.new_record? || series.changed?
      series
    end

    private

    def normalize_reference(reference)
      return reference if reference.is_a?(Importing::EventSeriesReference::Result)
      return if reference.blank?

      source_type = reference[:source_type] || reference["source_type"]
      source_key = reference[:source_key] || reference["source_key"]
      name = reference[:name] || reference["name"]
      return if source_type.blank? || source_key.blank?

      Importing::EventSeriesReference::Result.new(
        source_type: source_type.to_s,
        source_key: source_key.to_s,
        name: name.to_s.presence
      )
    end
  end
end
