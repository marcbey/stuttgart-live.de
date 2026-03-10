class AddHeroFocusPositionToEventImages < ActiveRecord::Migration[8.1]
  def change
    add_column :event_images, :hero_focus_position, :string
  end
end
