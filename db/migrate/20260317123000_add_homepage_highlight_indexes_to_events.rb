class AddHomepageHighlightIndexesToEvents < ActiveRecord::Migration[8.1]
  def change
    remove_index :events, :highlighted if index_exists?(:events, :highlighted)

    add_index :events, [ :start_at, :id ],
      name: "index_events_on_published_highlighted_start_at_and_id",
      where: "status = 'published' AND highlighted = TRUE"

    add_index :events, [ :promoter_id, :start_at, :id ],
      name: "index_events_on_published_promoter_id_start_at_and_id",
      where: "status = 'published'"
  end
end
