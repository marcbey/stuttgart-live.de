class EnablePgTrgmForVenueSearch < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :venues,
      "LOWER(name) gin_trgm_ops",
      using: :gin,
      name: "index_venues_on_lower_name_trgm"
  end

  def down
    remove_index :venues, name: "index_venues_on_lower_name_trgm"
    disable_extension "pg_trgm" if extension_enabled?("pg_trgm")
  end
end
