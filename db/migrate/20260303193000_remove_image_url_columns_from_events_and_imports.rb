class RemoveImageUrlColumnsFromEventsAndImports < ActiveRecord::Migration[8.1]
  def change
    remove_column :events, :image_url, :string
    remove_column :easyticket_import_events, :image_url, :string
    remove_column :eventim_import_events, :image_url, :string
  end
end
