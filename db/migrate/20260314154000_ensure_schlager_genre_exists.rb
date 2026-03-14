class EnsureSchlagerGenreExists < ActiveRecord::Migration[8.1]
  class Genre < ApplicationRecord
    self.table_name = "genres"
  end

  def up
    genre = Genre.find_or_initialize_by(slug: "schlager")
    genre.name = "Schlager"
    genre.save!
  end

  def down
    Genre.find_by(name: "Schlager", slug: "schlager")&.destroy!
  end
end
