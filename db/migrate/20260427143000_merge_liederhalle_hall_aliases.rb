class MergeLiederhalleHallAliases < ActiveRecord::Migration[8.1]
  CANONICAL_NAMES_BY_ALIAS = {
    "KKL Beethoven-Saal Stuttgart" => "Kultur- und Kongresszentrum Liederhalle Beethoven-Saal",
    "Liederhalle Beethovensaal" => "Kultur- und Kongresszentrum Liederhalle Beethoven-Saal",
    "Liederhalle Beethoven-Saal" => "Kultur- und Kongresszentrum Liederhalle Beethoven-Saal",
    "KKL Mozart-Saal Stuttgart" => "Kultur- und Kongresszentrum Liederhalle Mozart-Saal",
    "Liederhalle Mozartsaal" => "Kultur- und Kongresszentrum Liederhalle Mozart-Saal",
    "Mozartsaal Kultur- und Kongresszentrum Liederhalle Stuttgart" => "Kultur- und Kongresszentrum Liederhalle Mozart-Saal",
    "KKL Silcher-Saal Stuttgart" => "Kultur- und Kongresszentrum Liederhalle Silcher-Saal",
    "Liederhalle Silchersaal" => "Kultur- und Kongresszentrum Liederhalle Silcher-Saal",
    "KKL Hegel-Saal Stuttgart" => "Kultur- und Kongresszentrum Liederhalle Hegel-Saal",
    "KKL Hegel-Saal Konzert Stuttgart" => "Kultur- und Kongresszentrum Liederhalle Hegel-Saal",
    "Liederhalle Hegelsaal" => "Kultur- und Kongresszentrum Liederhalle Hegel-Saal",
    "Liederhalle Stuttgart - Hegelsaal" => "Kultur- und Kongresszentrum Liederhalle Hegel-Saal",
    "KKL Schiller-Saal Stuttgart" => "Kultur- und Kongresszentrum Liederhalle Schiller-Saal",
    "Liederhalle Schiller-Saal" => "Kultur- und Kongresszentrum Liederhalle Schiller-Saal"
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
    raise ActiveRecord::IrreversibleMigration, "Cannot safely restore merged Liederhalle hall aliases"
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
