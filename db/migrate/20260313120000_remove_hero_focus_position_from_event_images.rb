class RemoveHeroFocusPositionFromEventImages < ActiveRecord::Migration[8.1]
  def change
    remove_column :event_images, :hero_focus_position, :string
  end
end
