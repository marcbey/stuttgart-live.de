class ClearFallbackDoorsAtFromSourceSnapshots < ActiveRecord::Migration[8.1]
  class MigrationEvent < ApplicationRecord
    self.table_name = "events"
  end

  class MigrationRawEventImport < ApplicationRecord
    self.table_name = "raw_event_imports"
  end

  EVENTIM_DOORS_KEYS = %w[doors doorsat doors_at entrytime entry_time].freeze
  RESERVIX_DOORS_KEYS = %w[doors doorsat doors_at doorsopen doors_open entrytime entry_time].freeze

  def up
    say_with_time("Clearing fallback doors_at values from event source snapshots") do
      updated = 0

      MigrationEvent.find_each do |event|
        next unless event.source_snapshot.is_a?(Hash)

        sources = Array(event.source_snapshot["sources"])
        next if sources.empty?

        changed = false
        normalized_sources =
          sources.map do |source|
            normalized_source = source.is_a?(Hash) ? source.deep_stringify_keys : {}
            next normalized_source if normalized_source.empty?
            next normalized_source unless fallback_snapshot_doors_at?(normalized_source)
            next normalized_source if valid_doors_time_in_raw_import?(normalized_source)

            changed = true
            normalized_source.merge("doors_at" => nil)
          end

        next unless changed

        event.update_columns(
          source_snapshot: event.source_snapshot.merge("sources" => normalized_sources),
          updated_at: Time.current
        )
        updated += 1
      end

      updated
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot restore cleared fallback doors_at values in source_snapshot"
  end

  private

  def fallback_snapshot_doors_at?(source)
    doors_at = source["doors_at"].to_s.strip
    return false if doors_at.blank?

    fallback_time?(Time.zone.parse(doors_at))
  rescue ArgumentError
    false
  end

  def valid_doors_time_in_raw_import?(source)
    import_event_type = source["source"].to_s
    source_identifier = source["source_identifier"].to_s
    return false if import_event_type.blank? || source_identifier.blank?

    raw_import = latest_raw_import_for(import_event_type, source_identifier)
    return false if raw_import.nil?

    payload = raw_import.payload.is_a?(Hash) ? raw_import.payload.deep_stringify_keys : {}

    case import_event_type
    when "easyticket"
      valid_time_string?(
        payload["doors_at"].to_s.strip.presence ||
        payload["entry_time"].to_s.strip.presence ||
        payload.dig("data", "event", "doors_at").to_s.strip.presence
      )
    when "eventim"
      valid_time_string?(first_value_for_keys(payload, EVENTIM_DOORS_KEYS))
    when "reservix"
      valid_time_string?(first_value_for_keys(payload, RESERVIX_DOORS_KEYS))
    else
      false
    end
  end

  def latest_raw_import_for(import_event_type, source_identifier)
    MigrationRawEventImport.where(import_event_type:, source_identifier:)
      .order(created_at: :desc, id: :desc)
      .first
  end

  def first_value_for_keys(payload, keys)
    normalized_keys = keys.map { |key| normalize_key(key) }
    values = Hash.new { |hash, key| hash[key] = [] }
    collect_values_for_keys(payload, values)

    normalized_keys
      .flat_map { |key| values[key] }
      .map { |value| value.to_s.strip }
      .reject(&:blank?)
      .first
  end

  def collect_values_for_keys(node, values)
    case node
    when Hash
      node.each do |key, value|
        values[normalize_key(key)].concat(extract_scalar_values(value))
        collect_values_for_keys(value, values)
      end
    when Array
      node.each { |entry| collect_values_for_keys(entry, values) }
    end
  end

  def extract_scalar_values(value)
    case value
    when String, Numeric, TrueClass, FalseClass
      [ value.to_s ]
    when Array
      value.flat_map { |entry| extract_scalar_values(entry) }
    else
      []
    end
  end

  def normalize_key(value)
    value.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  def valid_time_string?(value)
    raw = value.to_s.strip
    return false if raw.blank?

    match = raw.match(/(?<!\d)(\d{1,2})[:.](\d{2})(?!\d)/)
    return false if match.blank?

    hour = match[1].to_i
    minute = match[2].to_i
    hour.between?(0, 23) && minute.between?(0, 59)
  end

  def fallback_time?(value)
    localized = value.in_time_zone(time_zone)
    localized.hour == 20 && localized.min == 0
  end

  def time_zone
    Time.zone.tzinfo.name
  end
end
