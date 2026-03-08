class ClearUnknownEventCities < ActiveRecord::Migration[8.0]
  def up
    change_column_null :events, :city, true
    Event.where(city: "Unbekannt").update_all(city: nil)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
