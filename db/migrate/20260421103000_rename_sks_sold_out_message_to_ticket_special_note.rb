class RenameSksSoldOutMessageToTicketSpecialNote < ActiveRecord::Migration[8.1]
  def change
    rename_column :events, :sks_sold_out_message, :ticket_special_note
  end
end
