require "date"
require "digest"
require "set"
require "uri"

module Importing
  module Easyticket
    class PayloadProjection
      URL_PATTERN = URI::DEFAULT_PARSER.make_regexp(%w[http https]).freeze
      URL_EXTRACT_PATTERN = %r{https?://[^\s"'<>]+}i.freeze

      def initialize(dump_payload:, detail_payload:, ticket_base_url: ENV["EASYTICKET_TICKET_LINK_EVENT_BASE_URL"])
        @dump_payload = dump_payload || {}
        @detail_payload = detail_payload || {}
        @ticket_base_url = ticket_base_url.to_s
      end

      def to_attributes
        external_event_id = dump_value("event_id")
        concert_date = parse_concert_date
        return nil if external_event_id.blank? || concert_date.nil?

        city = first_present(
          dump_value("loc_city"),
          dump_data_value("location", "city"),
          detail_value("city"),
          detail_value("location", "city"),
          detail_value("event", "city")
        )
        venue_name = first_present(
          dump_value("loc_name"),
          dump_data_value("location", "name"),
          dump_value("location_name"),
          detail_value("venue", "name"),
          detail_value("location", "name"),
          detail_value("event", "venue")
        )
        artist_title_fallback = first_present(
          dump_value("title"),
          dump_value("title_1"),
          dump_data_value("event", "title_1"),
          detail_value("title"),
          detail_value("event", "title")
        )
        title = first_present(
          dump_value("title_2"),
          dump_data_value("event", "title_2"),
          detail_value("title_2"),
          detail_value("event", "title_2"),
          dump_value("title"),
          dump_value("title_1"),
          dump_data_value("event", "title_1"),
          detail_value("title"),
          detail_value("event", "title")
        )
        artist_name = first_present(
          dump_value("sub1"),
          dump_value("artist"),
          artist_name_from_dump_titles,
          detail_value("artist_name"),
          detail_value("artist"),
          detail_value("event", "artist"),
          artist_title_fallback,
          title
        )
        artist_name = artist_title_fallback.presence || title if artist_name.blank? || artist_name.match?(/\A\d+\z/)
        organizer_id = first_present(
          dump_value("organizer_id"),
          dump_data_value("event", "organizer_id"),
          detail_value("organizer_id"),
          detail_value("event", "organizer_id")
        )

        city = city.presence
        venue_name = venue_name.presence || "Unbekannte Venue"
        title = title.presence || "Unbekanntes Event"

        {
          external_event_id: external_event_id,
          concert_date: concert_date,
          city: city,
          venue_name: venue_name,
          title: title,
          artist_name: artist_name,
          organizer_id: organizer_id.presence,
          concert_date_label: format_concert_date(concert_date),
          venue_label: format_venue(city, venue_name),
          ticket_url: build_ticket_url(external_event_id),
          source_payload_hash: Digest::SHA256.hexdigest(@dump_payload.to_json)
        }
      end

      def image_candidates
        candidates = []

        dump_image_candidates.each do |candidate|
          candidates << candidate.merge(position: candidates.length)
        end

        urls_from_dump_images.each do |url|
          candidates << { image_type: "images", image_url: url, position: candidates.length }
        end

        detail_roots.each do |root|
          images = root["images"]
          next unless images.is_a?(Array)

          images.each do |image|
            next unless image.is_a?(Hash)

            paths = image["paths"]
            next unless paths.is_a?(Array)

            paths.each do |path|
              next unless path.is_a?(Hash)

              url = ImportEventImage.normalize_image_url(path["url"])
              next if url.blank?

              type = path["type"].to_s.strip.presence || "detail_path"
              candidates << {
                image_type: type,
                image_url: url,
                position: candidates.length
              }
            end
          end
        end

        [
          [ "image_url", detail_value("image_url") ],
          [ "event_image_url", detail_value("event", "image_url") ],
          [ "event_image", detail_value("event", "image") ]
        ].each do |image_type, value|
          normalized = ImportEventImage.normalize_image_url(value)
          next if normalized.blank?

          candidates << {
            image_type: image_type,
            image_url: normalized,
            position: candidates.length
          }
        end

        deduplicate_candidates(candidates)
      end

      private

      def dump_value(key)
        @dump_payload[key].to_s.strip
      end

      def dump_data_value(*path)
        value = path.reduce(@dump_payload["data"]) do |memo, key|
          memo.respond_to?(:[]) ? memo[key] : nil
        end
        value.to_s.strip
      end

      def detail_value(*path)
        detail_roots.each do |root|
          value = path.reduce(root) do |memo, key|
            memo.respond_to?(:[]) ? memo[key] : nil
          end
          str = value.to_s.strip
          return str if str.present?
        end

        ""
      end

      def first_present(*values)
        values.map { |value| value.to_s.strip }.find(&:present?).to_s
      end

      def parse_concert_date
        raw = first_present(
          dump_value("date"),
          dump_value("date_time"),
          detail_value("start_date"),
          detail_value("event", "start_date"),
          detail_value("date"),
          detail_value("event", "date")
        )
        return nil if raw.blank?

        Date.parse(raw)
      rescue ArgumentError
        nil
      end

      def format_concert_date(date)
        "#{date.day}.#{date.month}.#{date.year}"
      end

      def format_venue(city, venue_name)
        [ city, venue_name ].reject(&:blank?).join(", ")
      end

      def build_ticket_url(external_event_id)
        dump_link = first_present(
          dump_value("ticket_url"),
          dump_value("ticket_link"),
          dump_data_value("event", "link"),
          detail_value("ticket_url"),
          detail_value("event", "ticket_url")
        )
        return dump_link if dump_link.present?
        return "" if @ticket_base_url.blank?

        if @ticket_base_url.include?("%{event_id}")
          format(@ticket_base_url, event_id: external_event_id)
        elsif @ticket_base_url.include?("{event_id}")
          @ticket_base_url.gsub("{event_id}", external_event_id)
        else
          normalized_base_url = @ticket_base_url.chomp("/")
          return normalized_base_url if normalized_base_url.end_with?("/#{external_event_id}")

          "#{normalized_base_url}/#{external_event_id}"
        end
      end

      def detail_roots
        @detail_roots ||=
          begin
            roots = [ @detail_payload ]
            data = @detail_payload["data"]
            roots << data if data.is_a?(Hash)
            roots
          end
      end

      def urls_from_dump_images
        dump_value("images").scan(URL_EXTRACT_PATTERN).filter_map do |value|
          ImportEventImage.normalize_image_url(value)
        end
      end

      def dump_image_candidates
        extract_dump_image_candidates(dump_images_for_event)
      end

      def dump_images_for_event
        event_id = dump_value("event_id")
        return nil if event_id.blank?

        images = @dump_payload.dig("data", "images")
        images ||= @dump_payload.dig("data", "Images")
        return nil unless images.is_a?(Hash)

        images[event_id] || images[event_id.to_i]
      end

      def extract_dump_image_candidates(value, image_type: "dump_image")
        case value
        when Array
          value.flat_map { |nested_value| extract_dump_image_candidates(nested_value, image_type: image_type) }
        when Hash
          candidates = []
          direct_type = value["type"].to_s.strip.presence || image_type

          %w[url src href image image_url].each do |key|
            next unless value[key].present?

            normalized_urls(value[key]).each do |url|
              candidates << { image_type: direct_type, image_url: url }
            end
          end

          value.each do |key, nested_value|
            next if %w[type url src href image image_url].include?(key.to_s)

            candidates.concat(extract_dump_image_candidates(nested_value, image_type: key.to_s))
          end

          candidates
        else
          normalized_urls(value).map do |url|
            { image_type: image_type, image_url: url }
          end
        end
      end

      def normalized_urls(value)
        value.to_s.scan(URL_EXTRACT_PATTERN).filter_map do |raw_url|
          ImportEventImage.normalize_image_url(raw_url)
        end
      end

      def artist_name_from_dump_titles
        primary_title = first_present(
          dump_value("title"),
          dump_value("title_1"),
          dump_data_value("event", "title_1")
        )
        secondary_title = first_present(
          dump_value("title_2"),
          dump_data_value("event", "title_2")
        )
        return "" if primary_title.blank? || secondary_title.blank?

        primary_title.downcase.include?(secondary_title.downcase) ? secondary_title : ""
      end

      def deduplicate_candidates(candidates)
        seen = Set.new

        candidates.filter_map do |candidate|
          image_url = candidate[:image_url].to_s
          dedupe_key = image_url.downcase
          next if seen.include?(dedupe_key)

          seen << dedupe_key
          candidate
        end
      end
    end
  end
end
