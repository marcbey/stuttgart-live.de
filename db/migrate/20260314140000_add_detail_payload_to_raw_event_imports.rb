class AddDetailPayloadToRawEventImports < ActiveRecord::Migration[8.1]
  def change
    add_column :raw_event_imports, :detail_payload, :jsonb, null: false, default: {}
  end
end
