class AddVvsTicketToVenues < ActiveRecord::Migration[8.1]
  def change
    add_column :venues, :vvs_ticket, :boolean, null: false, default: false
  end
end
