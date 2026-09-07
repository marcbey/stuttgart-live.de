class AddHighlightVideoOverlayToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :highlight_video_overlay_enabled, :boolean, default: false, null: false
  end
end
