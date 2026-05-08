class AddPublishedPromoterNameIndexToEvents < ActiveRecord::Migration[8.1]
  def change
    add_index :events, [ :promoter_name, :start_at, :id ],
      name: "index_events_on_published_promoter_name_start_at_and_id",
      where: "status = 'published' AND promoter_name IS NOT NULL"
  end
end
