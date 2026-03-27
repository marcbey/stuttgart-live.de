class AddPromoterNameToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :promoter_name, :string
  end
end
