class AddNormalizedArtistNameToEvents < ActiveRecord::Migration[8.0]
  class EventMigration < ActiveRecord::Base
    self.table_name = "events"
  end

  def up
    add_column :events, :normalized_artist_name, :string

    EventMigration.reset_column_information
    EventMigration.find_each do |event|
      normalized_artist_name = normalize_artist_name(event.artist_name)
      normalized_artist_name = normalize_artist_name(event.title) if normalized_artist_name.blank?
      normalized_artist_name = "event#{event.id}" if normalized_artist_name.blank?

      event.update_columns(normalized_artist_name: normalized_artist_name)
    end

    change_column_null :events, :normalized_artist_name, false
    add_index :events, [ :start_at, :normalized_artist_name ]
  end

  def down
    remove_index :events, [ :start_at, :normalized_artist_name ]
    remove_column :events, :normalized_artist_name
  end

  private

  def normalize_artist_name(value)
    normalized = I18n.transliterate(value.to_s).downcase
    normalized = normalized.tr("&", " ")
    normalized = normalized.gsub(/\bfeat(?:uring)?\b.*\z/i, " ")
    normalized = normalized.gsub(/\bft\.\b.*\z/i, " ")
    normalized = normalized.gsub(
      /\s*(?:[-,:+]|(?:\(|\[))?\s*(?:support|supports|special\s+guest|special\s+guests|presented\s+by|pres\.\s*by|live(?:\s+\d{4})?|on\s+tour|tour(?:\s+\d{4})?)\s*(?:\)|\])?\s*\z/i,
      ""
    )
    normalized.gsub(/[^a-z0-9]+/, "")
  end
end
