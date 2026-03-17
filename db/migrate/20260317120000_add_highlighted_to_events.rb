class AddHighlightedToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :highlighted, :boolean, default: false, null: false
    add_index :events, :highlighted
  end
end
