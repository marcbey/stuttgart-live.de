class RemoveArtistDescriptionFromEventLlmEnrichments < ActiveRecord::Migration[8.1]
  def change
    remove_column :event_llm_enrichments, :artist_description, :text
  end
end
