class NormalizeStaticGenreRecords < ActiveRecord::Migration[8.1]
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
    "Festivals & OpenAir",
    "Party & Night-Out",
    "Bildung & Wissen",
    "Kulinarik & Genuss",
    "Business, Coaching & Networking",
    "DIY & Kreativ",
    "Kultur, Führungen & Touren",
    "Sport & Bewegung"
  ].freeze

  LEGACY_GENRE_NAMES = {
    "Festivals/OpenAir" => "Festivals & OpenAir",
    "Party/ Night-Out" => "Party & Night-Out"
  }.freeze

  class MigrationGenre < ApplicationRecord
    self.table_name = "genres"
  end

  class MigrationEventGenre < ApplicationRecord
    self.table_name = "event_genres"
  end

  def up
    LEGACY_GENRE_NAMES.each do |legacy_name, static_name|
      normalize_genre!(legacy_name:, static_name:)
    end

    ensure_static_genres!
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def normalize_genre!(legacy_name:, static_name:)
    static_slug = static_name.parameterize
    legacy_genre = MigrationGenre.find_by(name: legacy_name) || MigrationGenre.find_by(slug: legacy_name.parameterize)
    static_genre = MigrationGenre.find_by(name: static_name) || MigrationGenre.find_by(slug: static_slug)

    if legacy_genre.present? && static_genre.present? && legacy_genre.id != static_genre.id
      move_event_genres!(from: legacy_genre, to: static_genre)
      legacy_genre.destroy!
      static_genre.update!(name: static_name, slug: static_slug)
    elsif legacy_genre.present?
      legacy_genre.update!(name: static_name, slug: static_slug)
    elsif static_genre.present?
      static_genre.update!(name: static_name, slug: static_slug)
    end
  end

  def ensure_static_genres!
    STATIC_GENRE_NAMES.each do |name|
      MigrationGenre.find_or_initialize_by(slug: name.parameterize).tap do |genre|
        genre.name = name
        genre.save!
      end
    end
  end

  def move_event_genres!(from:, to:)
    MigrationEventGenre.where(genre_id: from.id).find_each do |event_genre|
      if MigrationEventGenre.exists?(event_id: event_genre.event_id, genre_id: to.id)
        event_genre.destroy!
      else
        event_genre.update!(genre_id: to.id)
      end
    end
  end
end
