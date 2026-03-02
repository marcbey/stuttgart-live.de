require "date"
require "digest"
require "uri"

module Importing
  module Easyticket
    class PayloadProjection
      URL_PATTERN = URI::DEFAULT_PARSER.make_regexp(%w[http https]).freeze

      def initialize(dump_payload:, detail_payload:, ticket_base_url: ENV["TICKET_LINK_EVENT_BASE_URL"])
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
          detail_value("city"),
          detail_value("event", "city")
        )
        venue_name = first_present(
          dump_value("loc_name"),
          detail_value("venue", "name"),
          detail_value("event", "venue")
        )
        title = first_present(
          dump_value("title"),
          detail_value("title"),
          detail_value("event", "title")
        )
        artist_name = first_present(
          dump_value("sub1"),
          dump_value("artist"),
          detail_value("artist_name"),
          detail_value("artist"),
          detail_value("event", "artist"),
          title
        )
        artist_name = title if artist_name.blank? || artist_name.match?(/\A\d+\z/)

        city = city.presence || "Unbekannt"
        venue_name = venue_name.presence || "Unbekannte Venue"
        title = title.presence || "Unbekanntes Event"

        {
          external_event_id: external_event_id,
          concert_date: concert_date,
          city: city,
          venue_name: venue_name,
          title: title,
          artist_name: artist_name,
          concert_date_label: format_concert_date(concert_date),
          venue_label: format_venue(city, venue_name),
          ticket_url: build_ticket_url(external_event_id),
          image_url: extract_image_url,
          source_payload_hash: Digest::SHA256.hexdigest(@dump_payload.to_json)
        }
      end

      private

      def dump_value(key)
        @dump_payload[key].to_s.strip
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
          detail_value("ticket_url"),
          detail_value("event", "ticket_url")
        )
        return dump_link if dump_link.present?
        return "" if @ticket_base_url.blank?

        if @ticket_base_url.include?("%{event_id}")
          format(@ticket_base_url, event_id: external_event_id)
        else
          "#{@ticket_base_url.chomp('/')}/#{external_event_id}"
        end
      end

      def extract_image_url
        from_dump = dump_value("images")
        return Regexp.last_match(0) if from_dump.match(URL_PATTERN)

        from_details = extract_image_url_from_detail_payload
        return from_details if from_details.present?

        first_present(
          detail_value("image_url"),
          detail_value("event", "image_url"),
          detail_value("event", "image")
        )
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

      def extract_image_url_from_detail_payload
        detail_roots.each do |root|
          images = root["images"]
          next unless images.is_a?(Array)

          fallback = nil
          images.each do |image|
            next unless image.is_a?(Hash)

            paths = image["paths"]
            next unless paths.is_a?(Array)

            paths.each do |path|
              next unless path.is_a?(Hash)

              url = path["url"].to_s.strip
              next if url.blank?

              type = path["type"].to_s.strip.downcase
              return url if type == "large"
              fallback ||= url
            end
          end
          return fallback if fallback.present?
        end

        ""
      end
    end
  end
end
