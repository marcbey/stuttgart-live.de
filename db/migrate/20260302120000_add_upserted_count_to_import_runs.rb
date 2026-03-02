class AddUpsertedCountToImportRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :import_runs, :upserted_count, :integer, null: false, default: 0
  end
end
