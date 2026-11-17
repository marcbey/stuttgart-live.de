class AddCardDateOverrideToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :card_date_override, :string
  end
end
