class Genre < ApplicationRecord
  STATIC_NAMES = [
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

  has_many :event_genres, dependent: :destroy
  has_many :events, through: :event_genres

  validates :name, :slug, presence: true
  validates :name, :slug, uniqueness: true
  validate :name_must_be_static

  before_validation :normalize_attributes

  class << self
    def static_names
      STATIC_NAMES
    end

    def static_name?(value)
      static_names.include?(value.to_s.strip)
    end

    def static_options
      order(:name).pluck(:name, :id)
    end

    def ensure_static_records!
      static_names.each do |name|
        find_or_initialize_by(slug: name.parameterize).tap do |genre|
          genre.name = name
          genre.save!
        end
      end
    end
  end

  private

  def normalize_attributes
    self.name = name.to_s.strip
    self.slug = name.parameterize if slug.blank?
  end

  def name_must_be_static
    return if name.blank? || self.class.static_name?(name)

    errors.add(:name, "muss aus der statischen Genre-Liste stammen")
  end
end
