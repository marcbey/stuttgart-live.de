class MergeSchleyerHalleVenueAliases < ActiveRecord::Migration[8.1]
  CANONICAL_NAME = "Hanns-Martin-Schleyer-Halle"
  ALIAS_NAMES = [
    "Schleyer-Halle",
    "Schleyer-Halle Stuttgart",
    "Hanns-Martin-Schleyer-Halle Stuttgart"
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
        merge_blank_metadata!(canonical:, duplicate:)
        reassign_events!(canonical:, duplicate:)
        duplicate.delete
      end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Cannot safely restore merged Schleyer-Halle venue aliases"
  end

  private

  def merge_blank_metadata!(canonical:, duplicate:)
    attributes = {}
    attributes[:description] = duplicate.description if canonical.description.blank? && duplicate.description.present?
    attributes[:external_url] = duplicate.external_url if canonical.external_url.blank? && duplicate.external_url.present?
    attributes[:address] = duplicate.address if canonical.address.blank? && duplicate.address.present?
    return if attributes.empty?

    canonical.update!(attributes)
  end

  def reassign_events!(canonical:, duplicate:)
    MigrationEvent.where(venue_id: duplicate.id).update_all(
      venue_id: canonical.id,
      updated_at: Time.current
    )
  end
end
