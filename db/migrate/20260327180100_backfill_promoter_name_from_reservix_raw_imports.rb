class BackfillPromoterNameFromReservixRawImports < ActiveRecord::Migration[8.1]
  class MigrationEvent < ApplicationRecord
    self.table_name = "events"
  end

  class MigrationRawEventImport < ApplicationRecord
    self.table_name = "raw_event_imports"
  end

  def up
    say_with_time("Backfilling promoter_name from Reservix raw imports") do
      updated = 0

      MigrationEvent.where(promoter_name: [ nil, "" ]).find_each do |event|
        next unless event.source_snapshot.is_a?(Hash)

        normalized_sources = Array(event.source_snapshot["sources"]).map do |source|
          source.is_a?(Hash) ? source.deep_stringify_keys : {}
        end
        reservix_sources = normalized_sources.select { |source| source["source"].to_s == "reservix" }
        next if reservix_sources.empty?

        promoter_name = nil
        changed_snapshot = false

        normalized_sources = normalized_sources.map do |source|
          next source unless source["source"].to_s == "reservix"

          resolved_name = promoter_name_from_raw_import(source["source_identifier"])
          promoter_name ||= resolved_name

          if resolved_name.present? && source["promoter_name"].to_s.strip != resolved_name
            changed_snapshot = true
            source.merge("promoter_name" => resolved_name)
          else
            source
          end
        end

        next if promoter_name.blank? && !changed_snapshot

        attributes = { updated_at: Time.current }
        attributes[:promoter_name] = promoter_name if promoter_name.present?
        if changed_snapshot
          attributes[:source_snapshot] = event.source_snapshot.merge("sources" => normalized_sources)
        end

        event.update_columns(attributes)
        updated += 1
      end

      updated
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot restore blank promoter_name values after backfill"
  end

  private

  def promoter_name_from_raw_import(source_identifier)
    return nil if source_identifier.to_s.strip.blank?

    raw_import = MigrationRawEventImport.where(import_event_type: "reservix", source_identifier: source_identifier)
      .order(created_at: :desc, id: :desc)
      .first
    return nil if raw_import.nil?

    payload = raw_import.payload.is_a?(Hash) ? raw_import.payload.deep_stringify_keys : {}
    payload["publicOrganizerName"].to_s.strip.presence
  end
end
