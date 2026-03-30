module Venues
  class LlmFallbackAssignment
    def self.call(event:, enrichment:)
      return if event.blank? || enrichment.blank?

      venue = resolve_venue(event:, enrichment:)
      return if venue.blank?

      fill_blank_metadata(venue:, enrichment:)
      venue.save! if venue.changed?

      return if event.venue_record.present?

      event.venue_record = venue
      event.save! if event.changed?
    end

    def self.resolve_venue(event:, enrichment:)
      if event.venue_record.present?
        return event.venue_record if Venue.same_name?(event.venue_record.name, enrichment.venue)

        return
      end

      venue_name = Venue.normalize_name(enrichment.venue)
      return if venue_name.blank?

      Venue.find_by_normalized_name(venue_name) || Venue.create!(name: venue_name)
    end

    def self.fill_blank_metadata(venue:, enrichment:)
      venue_description = enrichment.venue_description.to_s.strip.presence
      venue_external_url = enrichment.venue_external_url.to_s.strip.presence
      venue_address = enrichment.venue_address.to_s.strip.presence

      venue.description = venue_description if venue.description.blank? && venue_description.present?
      venue.external_url = venue_external_url if venue.external_url.blank? && venue_external_url.present?
      venue.address = venue_address if venue.address.blank? && venue_address.present?
    end
  end
end
