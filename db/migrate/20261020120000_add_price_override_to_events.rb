class AddPriceOverrideToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :price_override, :string
  end
end
