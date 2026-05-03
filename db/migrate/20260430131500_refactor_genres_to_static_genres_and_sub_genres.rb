class RefactorGenresToStaticGenresAndSubGenres < ActiveRecord::Migration[8.1]
  STATIC_GENRE_NAMES = [
    "Pop, Indie & Singer-Songwriter",
    "Rock & Alternative",
    "Metal, Punk & Hardcore",
    "Hip-Hop & R’n’B",
    "Deutschrap",
    "Schlager & Volksmusik",
    "Techno & House",
    "Electronic Music & EDM",
    "Folk & Country",
    "Weltmusik",
    "Tribute & Cover",
    "Klassik & Oper",
    "Chor & Gospel",
    "Ausstellungen",
    "Jazz, Blues & Soul",
    "Musical & Theater",
    "Comedy & Kabarett",
    "Show, Varieté & Performance",
    "Lesung & Podcast",
    "Festivals/OpenAir",
    "Party/ Night-Out",
    "Bildung & Wissen",
    "Kulinarik & Genuss",
    "Business, Coaching & Networking",
    "DIY & Kreativ",
    "Kultur, Führungen & Touren",
    "Sport & Bewegung"
  ].freeze

  class MigrationGenre < ApplicationRecord
    self.table_name = "genres"
  end

  class MigrationSubGenre < ApplicationRecord
    self.table_name = "sub_genres"
  end

  class MigrationEventSubGenre < ApplicationRecord
    self.table_name = "event_sub_genres"
  end

  class MigrationEvent < ApplicationRecord
    self.table_name = "events"
  end

  class MigrationEventLlmEnrichment < ApplicationRecord
    self.table_name = "event_llm_enrichments"
  end

  class MigrationAppSetting < ApplicationRecord
    self.table_name = "app_settings"
  end

  def up
    remove_index :event_llm_enrichments, name: "index_event_llm_enrichments_on_genre" if index_exists?(:event_llm_enrichments, :genre, name: "index_event_llm_enrichments_on_genre")

    rename_table :genres, :sub_genres
    rename_index_if_exists :sub_genres, "index_genres_on_name", "index_sub_genres_on_name"
    rename_index_if_exists :sub_genres, "index_genres_on_slug", "index_sub_genres_on_slug"

    rename_table :event_genres, :event_sub_genres
    rename_column :event_sub_genres, :genre_id, :sub_genre_id
    rename_index_if_exists :event_sub_genres, "index_event_genres_on_event_id", "index_event_sub_genres_on_event_id"
    rename_index_if_exists :event_sub_genres, "index_event_genres_on_genre_id", "index_event_sub_genres_on_sub_genre_id"
    rename_index_if_exists :event_sub_genres, "index_event_genres_on_event_id_and_genre_id", "index_event_sub_genres_on_event_id_and_sub_genre_id"

    create_table :genres do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end

    add_index :genres, :name, unique: true
    add_index :genres, :slug, unique: true

    create_table :event_genres do |t|
      t.references :event, null: false, foreign_key: true
      t.references :genre, null: false, foreign_key: true
      t.timestamps
    end

    add_index :event_genres, [ :event_id, :genre_id ], unique: true

    seed_static_genres!
    backfill_sub_genres_from_llm_enrichments!
    remove_column :event_llm_enrichments, :genre, :jsonb, null: false, default: []

    drop_table :homepage_genre_lane_configurations if table_exists?(:homepage_genre_lane_configurations)
    drop_table :llm_genre_grouping_groups if table_exists?(:llm_genre_grouping_groups)
    drop_table :llm_genre_grouping_snapshots if table_exists?(:llm_genre_grouping_snapshots)

    delete_llm_genre_grouping_data!
    reset_homepage_genre_lanes!
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def rename_index_if_exists(table_name, old_name, new_name)
    rename_index table_name, old_name, new_name if index_name_exists?(table_name, old_name)
  end

  def seed_static_genres!
    MigrationGenre.reset_column_information

    STATIC_GENRE_NAMES.each do |name|
      MigrationGenre.find_or_initialize_by(slug: name.parameterize).tap do |genre|
        genre.name = name
        genre.save!
      end
    end
  end

  def backfill_sub_genres_from_llm_enrichments!
    MigrationSubGenre.reset_column_information
    MigrationEventSubGenre.reset_column_information
    MigrationEvent.reset_column_information
    MigrationEventLlmEnrichment.reset_column_information

    MigrationEventLlmEnrichment.find_each do |enrichment|
      next unless MigrationEvent.exists?(enrichment.event_id)

      Array(enrichment.genre).filter_map { |entry| entry.to_s.strip.presence }.uniq.each do |name|
        sub_genre = MigrationSubGenre.find_or_create_by!(slug: name.parameterize) do |record|
          record.name = name
        end
        MigrationEventSubGenre.find_or_create_by!(event_id: enrichment.event_id, sub_genre_id: sub_genre.id)
      end
    end
  end

  def delete_llm_genre_grouping_data!
    execute("DELETE FROM import_run_errors WHERE source_type = 'llm_genre_grouping'") if table_exists?(:import_run_errors)
    execute("DELETE FROM import_runs WHERE source_type = 'llm_genre_grouping'") if table_exists?(:import_runs)

    MigrationAppSetting.where(
      key: %w[
        llm_genre_grouping_model
        llm_genre_grouping_prompt_template
        llm_genre_grouping_group_count
        public_genre_grouping_snapshot_id
      ]
    ).delete_all

    delete_solid_queue_jobs!("Importing::LlmGenreGrouping::RunJob")
  end

  def reset_homepage_genre_lanes!
    setting = MigrationAppSetting.find_or_initialize_by(key: "homepage_genre_lane_slugs")
    setting.value = []
    setting.save!
  end

  def delete_solid_queue_jobs!(class_name)
    return unless table_exists?(:solid_queue_jobs)
    return unless column_exists?(:solid_queue_jobs, :class_name)

    %w[
      solid_queue_blocked_executions
      solid_queue_claimed_executions
      solid_queue_failed_executions
      solid_queue_ready_executions
      solid_queue_scheduled_executions
    ].each do |table_name|
      next unless table_exists?(table_name) && column_exists?(table_name, :job_id)

      execute(<<~SQL.squish)
        DELETE FROM #{table_name}
        WHERE job_id IN (
          SELECT id FROM solid_queue_jobs WHERE class_name = #{connection.quote(class_name)}
        )
      SQL
    end

    execute("DELETE FROM solid_queue_jobs WHERE class_name = #{connection.quote(class_name)}")
  end
end
