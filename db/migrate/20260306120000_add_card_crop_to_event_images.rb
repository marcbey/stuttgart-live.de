class AddCardCropToEventImages < ActiveRecord::Migration[8.1]
  def change
    add_column :event_images, :card_focus_x, :decimal, precision: 5, scale: 2, default: 50.0, null: false
    add_column :event_images, :card_focus_y, :decimal, precision: 5, scale: 2, default: 50.0, null: false
    add_column :event_images, :card_zoom, :decimal, precision: 5, scale: 2, default: 100.0, null: false
  end
end
