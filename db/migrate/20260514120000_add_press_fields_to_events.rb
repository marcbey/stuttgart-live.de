class AddPressFieldsToEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :publish_on_russ_live, :boolean
    add_column :events, :publish_slider_images_on_stuttgart_live, :boolean

    change_column_default :events, :publish_on_russ_live, from: nil, to: true
    change_column_default :events, :publish_slider_images_on_stuttgart_live, from: nil, to: true

    execute <<~SQL.squish
      UPDATE events
      SET publish_slider_images_on_stuttgart_live = TRUE
      WHERE id IN (
        SELECT DISTINCT event_id
        FROM event_images
        WHERE purpose = 'slider'
      )
    SQL
  end

  def down
    remove_column :events, :publish_slider_images_on_stuttgart_live
    remove_column :events, :publish_on_russ_live
  end
end
