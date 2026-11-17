class AddCardDateOverrideToEventSeries < ActiveRecord::Migration[8.1]
  def change
    add_column :event_series, :card_date_override, :string
  end
end
