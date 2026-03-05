class AddDoorsAtToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :doors_at, :datetime
  end
end
