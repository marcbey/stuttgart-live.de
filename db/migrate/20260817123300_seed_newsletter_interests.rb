class SeedNewsletterInterests < ActiveRecord::Migration[8.1]
  MAIN_GENRE_SLUGS = [
    "pop-indie-singer-songwriter",
    "rock-alternative",
    "metal-punk-hardcore",
    "hip-hop-r-n-b",
    "electronic-music-edm",
    "jazz-blues-soul",
    "klassik-oper",
    "musical-theater"
  ].freeze

  class GenreRecord < ActiveRecord::Base
    self.table_name = "genres"
  end

  class NewsletterInterestRecord < ActiveRecord::Base
    self.table_name = "newsletter_interests"
  end

  def up
    MAIN_GENRE_SLUGS.each_with_index do |genre_slug, index|
      genre = GenreRecord.find_by(slug: genre_slug)
      next if genre.blank?

      interest = NewsletterInterestRecord.find_or_initialize_by(slug: genre.slug)
      interest.genre_id = genre.id
      interest.name = label_for(genre.name)
      interest.mailjet_property_name = "interest_#{genre.slug.tr("-", "_")}"
      interest.position = index + 1
      interest.public_enabled = true
      interest.save!
    end
  end

  def down
    NewsletterInterestRecord.where(slug: MAIN_GENRE_SLUGS).delete_all
  end

  private

  def label_for(name)
    case name
    when "Pop, Indie & Singer-Songwriter" then "Pop"
    when "Rock & Alternative" then "Rock"
    when "Metal, Punk & Hardcore" then "Punk & Metal"
    when "Hip-Hop & R’n’B" then "Hip-Hop"
    when "Electronic Music & EDM" then "Electronic"
    when "Jazz, Blues & Soul" then "Jazz"
    when "Klassik & Oper" then "Klassik"
    when "Musical & Theater" then "Theater"
    else name
    end
  end
end
