module Newsletter
  class TeamTipProfiles
    Profile = Data.define(:key, :name, :role, :image_path)

    PROFILES = [
      Profile.new(key: "michaela-russ", name: "Michaela", role: "Geschäftsleitung", image_path: "newsletter/team/michaela.jpg"),
      Profile.new(key: "paul-woog", name: "Paul", role: "Geschäftsleitung", image_path: "newsletter/team/paul.jpg"),
      Profile.new(key: "johanna-backmund", name: "Johanna", role: "Projektmanagement / Accounting", image_path: "newsletter/team/johanna.jpg"),
      Profile.new(key: "sarah-sandner", name: "Sarah", role: "Marketing", image_path: "newsletter/team/sarah.jpg"),
      Profile.new(key: "katharina-schopper", name: "Kathi", role: "Grafik / Layout", image_path: "newsletter/team/kathi.jpg"),
      Profile.new(key: "chantal-erler", name: "Chantal", role: "Marketing Online / Social Media", image_path: "newsletter/team/chantal.jpg"),
      Profile.new(key: "tanja-ullenboom", name: "Tanja", role: "Produktionsleitung", image_path: "newsletter/team/tanja.jpg"),
      Profile.new(key: "michael-wechselberger", name: "Michi", role: "Personaldisposition", image_path: "newsletter/team/michi.jpg"),
      Profile.new(key: "tim-wilka", name: "Tim", role: "Ticketing", image_path: "newsletter/team/tim.jpg")
    ].freeze

    def self.all = PROFILES

    def self.find(key)
      all.find { |profile| profile.key == key.to_s }
    end
  end
end
