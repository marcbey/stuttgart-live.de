module Newsletter
  class HeaderGenreGroups
    Group = Data.define(:label, :slug, :genre)

    LABELS_BY_SLUG = {
      "pop-indie-singer-songwriter" => "Pop",
      "rock-alternative" => "Rock",
      "metal-punk-hardcore" => "Punk & Metal",
      "hip-hop-r-n-b" => "Hip-Hop",
      "electronic-music-edm" => "Electronic",
      "jazz-blues-soul" => "Jazz",
      "klassik-oper" => "Klassik",
      "musical-theater" => "Theater"
    }.freeze

    def self.all
      genres_by_slug = Genre.where(slug: NewsletterInterest::MAIN_GENRE_SLUGS).index_by(&:slug)

      NewsletterInterest::MAIN_GENRE_SLUGS.filter_map do |slug|
        genre = genres_by_slug[slug]
        next if genre.blank?

        Group.new(label: LABELS_BY_SLUG.fetch(slug, genre.name), slug:, genre:)
      end
    end
  end
end
