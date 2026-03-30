class BackfillVenueLocationFieldsFromLlmEnrichments < ActiveRecord::Migration[8.1]
  class MigrationVenue < ActiveRecord::Base
    self.table_name = "venues"
  end

  def up
    venue_data_by_id = Hash.new { |hash, key| hash[key] = {} }

    rows.each do |venue_id, venue_name, enrichment_venue_name, description, external_url, address|
      next unless venue_names_match?(venue_name, enrichment_venue_name)

      venue_data = venue_data_by_id[venue_id]
      venue_data[:description] ||= description.to_s.strip.presence
      venue_data[:external_url] ||= external_url.to_s.strip.presence
      venue_data[:address] ||= address.to_s.strip.presence
    end

    venue_data_by_id.each do |venue_id, attributes|
      next if attributes.empty?

      MigrationVenue.where(id: venue_id).update_all(attributes)
    end
  end

  def down
  end

  private

  def rows
    select_rows(<<~SQL.squish)
      SELECT
        events.venue_id,
        venues.name,
        event_llm_enrichments.venue,
        event_llm_enrichments.venue_description,
        event_llm_enrichments.venue_external_url,
        event_llm_enrichments.venue_address
      FROM event_llm_enrichments
      INNER JOIN events ON events.id = event_llm_enrichments.event_id
      INNER JOIN venues ON venues.id = events.venue_id
      WHERE
        COALESCE(event_llm_enrichments.venue_description, '') <> ''
        OR COALESCE(event_llm_enrichments.venue_external_url, '') <> ''
        OR COALESCE(event_llm_enrichments.venue_address, '') <> ''
      ORDER BY event_llm_enrichments.updated_at DESC, event_llm_enrichments.id DESC
    SQL
  end

  def venue_names_match?(left, right)
    normalize_venue_name(left).casecmp?(normalize_venue_name(right))
  end

  def normalize_venue_name(value)
    normalized = value.to_s.strip
    return normalized unless normalized.match?(/kulturquartier/i)

    normalized.gsub(/\s*[-,]?\s*proton\b/i, "").strip
  end
end
