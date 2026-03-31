class AddSksSoldOutMessageToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :sks_sold_out_message, :text
  end
end
