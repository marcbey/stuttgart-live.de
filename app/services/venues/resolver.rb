module Venues
  class Resolver
    def self.call(name:, venue_id: nil)
      selected_venue = Venue.find_by(id: venue_id) if venue_id.present?
      normalized_name = Venue.normalize_name(name)

      if selected_venue.present?
        return selected_venue if normalized_name.blank? ||
          Venue.same_name?(selected_venue.name, normalized_name) ||
          Venue.alias_maps_to_venue?(normalized_name, selected_venue)
      end

      return nil if normalized_name.blank?

      mapped_venue = Venue.canonical_alias_venue_for(normalized_name)
      return mapped_venue if mapped_venue.present?

      Venue.find_by_match_name(normalized_name) || Venue.new(name: normalized_name)
    end
  end
end
