class ReplaceImportEventTablesWithRawEventImports < ActiveRecord::Migration[8.1]
  class MigrationRawEventImport < ActiveRecord::Base
    self.table_name = "raw_event_imports"
  end

  class MigrationEasyticketImportEvent < ActiveRecord::Base
    self.table_name = "easyticket_import_events"
  end

  class MigrationEventimImportEvent < ActiveRecord::Base
    self.table_name = "eventim_import_events"
  end

  class MigrationReservixImportEvent < ActiveRecord::Base
    self.table_name = "reservix_import_events"
  end

  LEGACY_IMPORT_CLASSES = %w[
    EasyticketImportEvent
    EventimImportEvent
    ReservixImportEvent
  ].freeze

  def up
    create_table :raw_event_imports do |t|
      t.references :import_source, null: false, foreign_key: true
      t.string :import_event_type, null: false
      t.string :source_identifier, null: false
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :raw_event_imports, [ :import_event_type, :created_at ]
    add_index :raw_event_imports,
      [ :import_event_type, :source_identifier, :created_at ],
      name: "index_raw_event_imports_on_type_identifier_created_at"

    backfill_raw_event_imports!
    remove_legacy_import_images!

    drop_table :easyticket_import_events
    drop_table :eventim_import_events
    drop_table :reservix_import_events
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "raw_event_imports replaced the legacy import event tables"
  end

  private

  def backfill_raw_event_imports!
    backfill_table!(
      model: MigrationEasyticketImportEvent,
      import_event_type: "easyticket"
    ) do |row|
      payload =
        if row.detail_payload.is_a?(Hash) && row.detail_payload.present?
          row.detail_payload
        else
          row.dump_payload
        end

      {
        import_source_id: row.import_source_id,
        import_event_type: "easyticket",
        source_identifier: [ row.external_event_id, row.concert_date&.iso8601 ].compact.join(":"),
        payload: payload.is_a?(Hash) ? payload : {},
        created_at: row.created_at,
        updated_at: row.updated_at
      }
    end

    backfill_table!(
      model: MigrationEventimImportEvent,
      import_event_type: "eventim"
    ) do |row|
      {
        import_source_id: row.import_source_id,
        import_event_type: "eventim",
        source_identifier: [ row.external_event_id, row.concert_date&.iso8601 ].compact.join(":"),
        payload: row.dump_payload.is_a?(Hash) ? row.dump_payload : {},
        created_at: row.created_at,
        updated_at: row.updated_at
      }
    end

    backfill_table!(
      model: MigrationReservixImportEvent,
      import_event_type: "reservix"
    ) do |row|
      {
        import_source_id: row.import_source_id,
        import_event_type: "reservix",
        source_identifier: row.external_event_id.to_s,
        payload: row.dump_payload.is_a?(Hash) ? row.dump_payload : {},
        created_at: row.created_at,
        updated_at: row.updated_at
      }
    end
  end

  def backfill_table!(model:, import_event_type:)
    say_with_time("Backfilling #{import_event_type} rows into raw_event_imports") do
      rows = model.find_each.map { |row| yield(row) }
      rows.each_slice(500) do |slice|
        MigrationRawEventImport.insert_all!(slice)
      end
    end
  end

  def remove_legacy_import_images!
    execute <<~SQL.squish
      DELETE FROM import_event_images
      WHERE import_class IN (#{LEGACY_IMPORT_CLASSES.map { |value| quote(value) }.join(", ")})
    SQL
  end
end
