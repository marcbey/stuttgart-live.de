class RenameLiederhalleHallCanonicalVenues < ActiveRecord::Migration[8.1]
  RENAMES = {
    "KKL Beethoven-Saal" => "Kultur- und Kongresszentrum Liederhalle Beethoven-Saal",
    "KKL Mozart-Saal" => "Kultur- und Kongresszentrum Liederhalle Mozart-Saal",
    "KKL Silcher-Saal" => "Kultur- und Kongresszentrum Liederhalle Silcher-Saal",
    "KKL Hegel-Saal" => "Kultur- und Kongresszentrum Liederhalle Hegel-Saal",
    "KKL Schiller-Saal" => "Kultur- und Kongresszentrum Liederhalle Schiller-Saal"
  }.freeze

  class MigrationVenue < ActiveRecord::Base
    self.table_name = "venues"
  end

  def up
    RENAMES.each do |old_name, new_name|
      venue = MigrationVenue.find_by(name: old_name)
      next unless venue

      existing_target = MigrationVenue.find_by(name: new_name)

      if existing_target.present?
        raise ActiveRecord::IrreversibleMigration, "Target venue #{new_name} already exists"
      end

      venue.update!(name: new_name)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot safely restore renamed Liederhalle hall venues"
  end
end
