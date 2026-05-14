class RemovePressFieldDefaultsFromEvents < ActiveRecord::Migration[8.1]
  def change
    change_column_default :events, :publish_on_russ_live, from: true, to: nil
    change_column_default :events, :publish_slider_images_on_stuttgart_live, from: true, to: nil
  end
end
