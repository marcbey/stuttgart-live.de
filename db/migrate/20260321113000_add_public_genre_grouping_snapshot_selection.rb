class AddPublicGenreGroupingSnapshotSelection < ActiveRecord::Migration[8.1]
  class MigrationAppSetting < ApplicationRecord
    self.table_name = "app_settings"
  end

  class MigrationSnapshot < ApplicationRecord
    self.table_name = "llm_genre_grouping_snapshots"
  end

  class MigrationHomepageGenreLaneConfiguration < ApplicationRecord
    self.table_name = "homepage_genre_lane_configurations"
  end

  LEGACY_HOMEPAGE_GENRE_LANE_SLUGS_KEY = "homepage_genre_lane_slugs".freeze
  PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY = "public_genre_grouping_snapshot_id".freeze

  def up
    create_table :homepage_genre_lane_configurations do |t|
      t.references :snapshot, null: false, foreign_key: { to_table: :llm_genre_grouping_snapshots }, index: { unique: true }
      t.jsonb :lane_slugs, null: false, default: []
      t.timestamps
    end

    migrate_existing_homepage_genre_lane_configuration!
  end

  def down
    MigrationAppSetting.where(key: PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY).delete_all
    drop_table :homepage_genre_lane_configurations
  end

  private

  def migrate_existing_homepage_genre_lane_configuration!
    legacy_snapshot = MigrationSnapshot.where(active: true).order(id: :desc).first
    return if legacy_snapshot.blank?

    MigrationAppSetting.find_or_create_by!(key: PUBLIC_GENRE_GROUPING_SNAPSHOT_ID_KEY) do |setting|
      setting.value = legacy_snapshot.id
    end

    legacy_slugs = MigrationAppSetting.find_by(key: LEGACY_HOMEPAGE_GENRE_LANE_SLUGS_KEY)&.value

    MigrationHomepageGenreLaneConfiguration.find_or_create_by!(snapshot_id: legacy_snapshot.id) do |configuration|
      configuration.lane_slugs = normalize_slug_list(legacy_slugs)
    end
  end

  def normalize_slug_list(value)
    raw_values =
      case value
      when String
        value.split(/[\n,]/)
      when Array
        value
      else
        Array(value)
      end

    raw_values
      .map { |entry| entry.to_s.parameterize.presence }
      .compact
      .uniq
  end
end
