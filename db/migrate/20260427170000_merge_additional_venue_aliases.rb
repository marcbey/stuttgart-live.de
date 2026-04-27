class MergeAdditionalVenueAliases < ActiveRecord::Migration[8.1]
  CANONICAL_NAMES_BY_ALIAS = {
    "Kulinarium an der Glems/Römerhof" => "Kulinarium an der Glems",
    "Kulturquartier" => "Kulturquartier (Proton)",
    "Kulturquartier Stuttgart ( the Club)" => "Kulturquartier (Proton)",
    "Kulturquartier Stuttgart" => "Kulturquartier (Proton)",
    "Kulturquartier - PROTON" => "Kulturquartier (Proton)",
    "Schräglage Club" => "Schräglage",
    "Schräglage Stuttgart" => "Schräglage",
    "FITZ! Zentrum für Figurentheater" => "FITZ! Figurentheater",
    "FITZ Das Theater animierter Formen" => "FITZ! Figurentheater",
    "FITZ" => "FITZ! Figurentheater",
    "Das K - Kultur- und Kongresszentrum - Theatersaal" => "Das K-Kultur-und Kongresszentrum",
    "Das K – Kulturzentrum (Festsaal)" => "Das K-Kultur-und Kongresszentrum",
    "Das K - Kultur- und Kongresszentrum - Festsaal" => "Das K-Kultur-und Kongresszentrum"
  }.freeze

  class MigrationVenue < ActiveRecord::Base
    self.table_name = "venues"
  end

  class MigrationEvent < ActiveRecord::Base
    self.table_name = "events"
  end

  def up
    grouped_aliases.each do |canonical_name, aliases|
      canonical = MigrationVenue.find_or_create_by!(name: canonical_name)

      MigrationVenue
        .where("LOWER(name) IN (?)", aliases.map(&:downcase))
        .where.not(id: canonical.id)
        .find_each do |duplicate|
          reassign_events!(canonical:, duplicate:)
          duplicate.delete
        end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot safely restore merged venue aliases"
  end

  private

  def grouped_aliases
    @grouped_aliases ||= CANONICAL_NAMES_BY_ALIAS.group_by { |_, canonical_name| canonical_name }
      .transform_values { |pairs| pairs.map(&:first) }
  end

  def reassign_events!(canonical:, duplicate:)
    MigrationEvent.where(venue_id: duplicate.id).update_all(
      venue_id: canonical.id,
      updated_at: Time.current
    )
  end
end
