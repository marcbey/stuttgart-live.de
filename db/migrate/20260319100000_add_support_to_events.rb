class AddSupportToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :support, :string
  end
end
