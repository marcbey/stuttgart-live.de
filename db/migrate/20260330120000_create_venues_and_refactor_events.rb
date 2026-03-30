require "set"

class CreateVenuesAndRefactorEvents < ActiveRecord::Migration[8.1]
  class MigrationVenue < ApplicationRecord
    self.table_name = "venues"
  end

  class MigrationEvent < ApplicationRecord
    self.table_name = "events"
  end

  class MigrationEnrichment < ApplicationRecord
    self.table_name = "event_llm_enrichments"
  end

  def up
    create_table :venues do |t|
      t.string :name, null: false
      t.text :description
      t.string :external_url
      t.text :address
      t.timestamps
    end

    add_index :venues, "LOWER(name)", unique: true, name: "index_venues_on_lower_name"
    add_reference :events, :venue, foreign_key: { to_table: :venues }, null: true

    MigrationVenue.reset_column_information
    MigrationEvent.reset_column_information
    MigrationEnrichment.reset_column_information

    backfill_venues!

    change_column_null :events, :venue_id, false
    remove_column :events, :venue, :string
  end

  def down
    add_column :events, :venue, :string

    MigrationVenue.reset_column_information
    MigrationEvent.reset_column_information

    MigrationEvent.find_each do |event|
      venue_name = MigrationVenue.where(id: event.venue_id).pick(:name)
      event.update_columns(venue: venue_name.to_s.strip.presence || "Unbekannte Venue")
    end

    remove_reference :events, :venue, foreign_key: { to_table: :venues }
    remove_table :venues
  end

  private

  def backfill_venues!
    venue_ids_by_name = {}

    MigrationEvent.find_each do |event|
      normalized_name = normalize_venue_name(event.read_attribute(:venue))
      next if normalized_name.blank?

      lookup_key = normalized_name.downcase
      venue_ids_by_name[lookup_key] ||= begin
        MigrationVenue.where("LOWER(name) = ?", lookup_key).pick(:id) || MigrationVenue.create!(name: normalized_name).id
      end

      event.update_columns(venue_id: venue_ids_by_name[lookup_key])
    end

    seen_venue_ids = Set.new

    MigrationEnrichment
      .joins("INNER JOIN events ON events.id = event_llm_enrichments.event_id")
      .joins("INNER JOIN venues ON venues.id = events.venue_id")
      .where.not(event_llm_enrichments: { venue_description: [ nil, "" ] })
      .order(updated_at: :desc, id: :desc)
      .pluck("events.venue_id", "venues.name", "event_llm_enrichments.venue", "event_llm_enrichments.venue_description")
      .each do |venue_id, venue_name, enrichment_venue_name, description|
        next if seen_venue_ids.include?(venue_id)
        next unless venue_names_match?(venue_name, enrichment_venue_name)

        MigrationVenue.where(id: venue_id).update_all(description: description.to_s.strip)
        seen_venue_ids << venue_id
      end
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
