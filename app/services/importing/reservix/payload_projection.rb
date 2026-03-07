require "bigdecimal"
require "date"
require "digest"
require "set"

module Importing
  module Reservix
    class PayloadProjection
      def initialize(event_payload:)
        @event_payload = (event_payload || {}).deep_stringify_keys
        @references = @event_payload["references"].is_a?(Hash) ? @event_payload["references"].deep_stringify_keys : {}
      end

      def to_attributes
        external_event_id = @event_payload["id"].to_s.strip
        concert_date = parse_concert_date
        return nil if external_event_id.blank? || concert_date.nil?

        title = @event_payload["name"].to_s.strip.presence || "Unbekanntes Event"
        artist_name = @event_payload["artist"].to_s.strip.presence || title
        city = venue_reference["city"].to_s.strip.presence || location_city_fallback || "Unbekannt"
        venue_name = extract_venue_name.presence || "Unbekannte Venue"
        organizer_name = organizer_reference["name"].to_s.strip.presence || @event_payload["publicOrganizerName"].to_s.strip.presence

        min_price = parse_decimal(@event_payload["minPrice"])
        max_price = parse_decimal(@event_payload["maxPrice"])
        min_price ||= max_price
        max_price ||= min_price

        {
          external_event_id: external_event_id,
          concert_date: concert_date,
          city: city,
          venue_name: venue_name,
          title: title,
          artist_name: artist_name,
          organizer_name: organizer_name,
          min_price: min_price,
          max_price: max_price,
          concert_date_label: format_concert_date(concert_date),
          venue_label: format_venue(city, venue_name),
          ticket_url: ticket_url,
          source_payload_hash: Digest::SHA256.hexdigest(@event_payload.to_json)
        }
      end

      def image_candidates
        candidates = []
        seen = Set.new

        Array(@references["image"]).each do |entry|
          image = entry.is_a?(Hash) ? entry.deep_stringify_keys : {}
          next if ActiveModel::Type::Boolean.new.cast(image["isPlaceholder"])

          type = Integer(image["type"], exception: false)
          image_type =
            case type
            when 1 then "detail"
            when 2 then "slideshow"
            else "image"
            end
          role =
            case type
            when 1 then "cover"
            when 2 then "gallery"
            else "gallery"
            end

          [
            [ image["url"], image_type, role ],
            [ image["thumbnail_url"], "#{image_type}_thumbnail", "thumb" ]
          ].each do |url, candidate_type, candidate_role|
            normalized_url = ImportEventImage.normalize_image_url(url)
            next if normalized_url.blank?

            key = [ candidate_type, normalized_url.downcase ]
            next if seen.include?(key)

            seen << key
            candidates << {
              image_type: candidate_type,
              image_url: normalized_url,
              role: candidate_role,
              position: candidates.length
            }
          end
        end

        candidates
      end

      def bookable?
        ActiveModel::Type::Boolean.new.cast(@event_payload["bookable"])
      end

      def modified_at
        raw = @event_payload["modified"].to_s.strip
        return nil if raw.blank?

        Time.zone.parse(raw)
      rescue ArgumentError
        nil
      end

      private

      def parse_concert_date
        raw = @event_payload["startdate"].to_s.strip
        return nil if raw.blank?

        Date.parse(raw)
      rescue ArgumentError
        nil
      end

      def parse_decimal(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        BigDecimal(raw)
      rescue ArgumentError
        nil
      end

      def ticket_url
        @event_payload["affiliateSaleUrl"].to_s.strip.presence ||
          @event_payload["canonicalUrl"].to_s.strip.presence ||
          @event_payload["publicSaleUrl"].to_s.strip.presence
      end

      def extract_venue_name
        location_reference["name"].to_s.strip.presence ||
          venue_reference["name"].to_s.strip.presence ||
          formatted_name_prefix(location_reference["formatted"]) ||
          formatted_name_prefix(venue_reference["formatted"])
      end

      def location_city_fallback
        formatted = location_reference["formatted"].to_s.strip
        return nil if formatted.blank?

        formatted.split(",").last.to_s.strip.split(/\s+/, 2).last.to_s.strip.presence
      end

      def formatted_name_prefix(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        raw.split(" - ").first.to_s.strip.presence
      end

      def event_reference(key)
        Array(@references[key]).find { |entry| entry.is_a?(Hash) }&.deep_stringify_keys || {}
      end

      def location_reference
        @location_reference ||= event_reference("location")
      end

      def venue_reference
        @venue_reference ||= event_reference("venue")
      end

      def organizer_reference
        @organizer_reference ||= event_reference("organizer")
      end

      def format_concert_date(date)
        "#{date.day}.#{date.month}.#{date.year}"
      end

      def format_venue(city, venue_name)
        [ city, venue_name ].reject(&:blank?).join(", ")
      end
    end
  end
end
