class AddVenueLocationFieldsToEventLlmEnrichments < ActiveRecord::Migration[8.1]
  def change
    add_column :event_llm_enrichments, :venue_external_url, :string
    add_column :event_llm_enrichments, :venue_address, :text
  end
end
