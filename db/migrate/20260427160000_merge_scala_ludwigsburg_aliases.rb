class MergeScalaLudwigsburgAliases < ActiveRecord::Migration[8.1]
  CANONICAL_NAME = "Scala Ludwigsburg"
  ALIAS_NAMES = [
    "Scala",
    "Scala Theater Ludwigsburg"
  ].freeze

  class MigrationVenue < ActiveRecord::Base
    self.table_name = "venues"
  end

  class MigrationEvent < ActiveRecord::Base
    self.table_name = "events"
  end

  def up
    canonical = MigrationVenue.find_or_create_by!(name: CANONICAL_NAME)

    MigrationVenue
      .where("LOWER(name) IN (?)", ALIAS_NAMES.map(&:downcase))
      .where.not(id: canonical.id)
      .find_each do |duplicate|
        reassign_events!(canonical:, duplicate:)
        duplicate.delete
      end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot safely restore merged Scala Ludwigsburg venue aliases"
  end

  private

  def reassign_events!(canonical:, duplicate:)
    MigrationEvent.where(venue_id: duplicate.id).update_all(
      venue_id: canonical.id,
      updated_at: Time.current
    )
  end
end
