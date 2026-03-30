module Venues
  class Resolver
    def self.call(name:, venue_id: nil)
      selected_venue = Venue.find_by(id: venue_id) if venue_id.present?
      normalized_name = Venue.normalize_name(name)

      if selected_venue.present?
        return selected_venue if normalized_name.blank? || Venue.same_name?(selected_venue.name, normalized_name)
      end

      return nil if normalized_name.blank?

      Venue.find_by_normalized_name(normalized_name) || Venue.new(name: normalized_name)
    end
  end
end
