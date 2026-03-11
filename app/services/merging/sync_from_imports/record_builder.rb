require "bigdecimal"
require "cgi"

module Merging
  class SyncFromImports
    class RecordBuilder
      def initialize(priority_map:)
        @priority_map = priority_map
      end

      def import_records
        ImportSource::SOURCE_TYPES.flat_map { |source| import_records_for(source) }
      end

      private

      attr_reader :priority_map

      def import_records_for(source)
        import_model_for(source)
          .active
          .includes(:import_event_images)
          .joins(:import_source)
          .where(import_sources: { active: true, source_type: source })
          .map do |record|
            build_import_record(record, source: source)
          end
      end

      def import_model_for(source)
        case source
        when "easyticket"
          EasyticketImportEvent
        when "eventim"
          EventimImportEvent
        when "reservix"
          ReservixImportEvent
        else
          raise ArgumentError, "Unsupported import source: #{source.inspect}"
        end
      end

      def build_import_record(record, source:)
        ensure_import_record_images!(record, source: source)

        ImportRecord.new(
          source: source,
          external_event_id: record.external_event_id,
          concert_date: record.concert_date,
          begin_time: import_record_begin_time(record, source: source),
          city: record.city,
          venue_name: record.venue_name,
          title: record.title,
          artist_name: record.artist_name,
          promoter_id: import_record_promoter_id(record, source: source),
          description_text: import_record_description_text(record, source: source),
          ticket_url: record.ticket_url,
          ticket_price_text: import_record_ticket_price_text(record, source: source),
          min_price: import_record_min_price(record, source: source),
          max_price: import_record_max_price(record, source: source),
          images: images_for_import_record(record, fallback_source: source),
          raw_payload: import_record_raw_payload(record)
        )
      end

      def ensure_import_record_images!(record, source:)
        association = record.import_event_images
        return if association.loaded? ? association.any? : association.exists?

        candidates =
          case source
          when "easyticket"
            Importing::Easyticket::PayloadProjection.new(
              dump_payload: record.dump_payload,
              detail_payload: record.detail_payload
            ).image_candidates
          when "eventim"
            Importing::Eventim::PayloadProjection.new(
              feed_payload: record.dump_payload
            ).image_candidates
          when "reservix"
            Importing::Reservix::PayloadProjection.new(
              event_payload: record.dump_payload
            ).image_candidates
          else
            []
          end

        Importing::ImportEventImagesSync.call(owner: record, source: source, candidates: candidates)
        association.reset
      end

      def images_for_import_record(record, fallback_source:)
        record.import_event_images.ordered.map do |image|
          source = image.source.to_s.strip.presence || fallback_source
          image_type = image.image_type.to_s.strip.presence || "image"
          image_url = ImportEventImage.normalize_image_url(image.image_url)
          next if image_url.blank?

          ImportImage.new(
            source: source,
            image_type: image_type,
            image_url: image_url,
            role: image.role.to_s.strip.presence || ImportEventImage.derive_role(source: source, image_type: image_type),
            aspect_hint: image.aspect_hint.to_s.strip.presence || ImportEventImage.derive_aspect_hint(url: image_url, image_type: image_type),
            position: image.position.to_i
          )
        end.compact
      end

      def import_record_begin_time(record, source:)
        send("begin_time_for_#{source}", record)
      end

      def import_record_promoter_id(record, source:)
        case source
        when "easyticket"
          promoter_id_for_easyticket(record)
        when "eventim"
          promoter_id_for_eventim(record)
        else
          nil
        end
      end

      def import_record_description_text(record, source:)
        send("description_text_for_#{source}", record)
      end

      def import_record_ticket_price_text(record, source:)
        send("ticket_price_text_for_#{source}", record)
      end

      def import_record_min_price(record, source:)
        source == "reservix" ? record.min_price : nil
      end

      def import_record_max_price(record, source:)
        source == "reservix" ? record.max_price : nil
      end

      def import_record_raw_payload(record)
        {
          dump_payload: record.dump_payload,
          detail_payload: record.detail_payload
        }
      end

      def promoter_id_for_easyticket(record)
        detail_payload = record.detail_payload.is_a?(Hash) ? record.detail_payload.deep_stringify_keys : {}

        first_non_blank(
          detail_payload.dig("data", "organizer_id"),
          detail_payload.dig("data", "event", "organizer_id"),
          record.organizer_id,
          Importing::Easyticket::PayloadProjection.new(
            dump_payload: record.dump_payload,
            detail_payload: record.detail_payload
          ).to_attributes&.dig(:organizer_id)
        ).to_s.strip
      end

      def promoter_id_for_eventim(record)
        return record.promoter_id.to_s.strip if record.promoter_id.to_s.strip.present?

        projection = Importing::Eventim::PayloadProjection.new(feed_payload: record.dump_payload)
        projection.to_attributes&.dig(:promoter_id).to_s.strip
      end

      def begin_time_for_easyticket(record)
        raw_payload = raw_dump_payload_for(record)
        raw_payload["time"].to_s.strip.presence || parse_time_from_datetime(raw_payload["date_time"])
      end

      def begin_time_for_eventim(record)
        raw_payload = raw_dump_payload_for(record)
        raw_payload["eventtime"].to_s.strip
      end

      def ticket_price_text_for_easyticket(record)
        raw_payload = raw_dump_payload_for(record)
        raw_payload["price_text"].to_s.strip.presence || format_easyticket_price_range(raw_payload)
      end

      def description_text_for_easyticket(record)
        raw_payload = raw_dump_payload_for(record)
        normalize_import_description(raw_payload["text"].presence || raw_payload["description"])
      end

      def ticket_price_text_for_eventim(record)
        categories = eventim_price_categories_for(record)
        prices = categories.filter_map do |entry|
          parse_price_decimal(entry["price"] || entry[:price])
        end
        return nil if prices.empty?

        currency =
          categories
            .filter_map { |entry| (entry["currency"] || entry[:currency]).to_s.strip.presence }
            .first || "EUR"

        min_price = prices.min
        max_price = prices.max

        if min_price == max_price
          "#{format_price_decimal(min_price)} #{currency}"
        else
          "#{format_price_decimal(min_price)} - #{format_price_decimal(max_price)} #{currency}"
        end
      end

      def begin_time_for_reservix(record)
        raw_payload = raw_dump_payload_for(record)
        raw_payload["starttime"].to_s.strip
      end

      def ticket_price_text_for_reservix(record)
        format_price_range(record.min_price, record.max_price)
      end

      def description_text_for_reservix(record)
        raw_payload = raw_dump_payload_for(record)
        normalize_import_description(raw_payload["description"])
      end

      def description_text_for_eventim(record)
        raw_payload = raw_dump_payload_for(record)
        raw_description =
          raw_payload["estext"].to_s.strip.presence ||
          raw_payload["esinfo"].to_s.strip.presence ||
          raw_payload["text"].to_s.strip.presence

        normalize_import_description(raw_description)
      end

      def eventim_price_categories_for(record)
        raw_payload = raw_dump_payload_for(record)
        value = raw_payload["pricecategory"] || raw_payload["priceCategory"] || raw_payload["price_category"]
        case value
        when Array
          value.filter_map { |entry| entry.is_a?(Hash) ? entry : nil }
        when Hash
          [ value ]
        else
          []
        end
      end

      def parse_price_decimal(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        normalized = raw.gsub(/[^0-9,.\-]/, "")
        return nil if normalized.blank?

        if normalized.include?(",") && normalized.include?(".")
          if normalized.rindex(",") > normalized.rindex(".")
            normalized = normalized.delete(".").tr(",", ".")
          else
            normalized = normalized.delete(",")
          end
        elsif normalized.include?(",")
          normalized = normalized.tr(",", ".")
        end

        BigDecimal(normalized)
      rescue ArgumentError
        nil
      end

      def parse_time_from_datetime(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        Time.zone.parse(raw)&.strftime("%H:%M")
      rescue ArgumentError, TypeError
        nil
      end

      def format_easyticket_price_range(raw_payload)
        min_price = parse_price_decimal(raw_payload["price_start"])
        max_price = parse_price_decimal(raw_payload["price_end"])
        return nil unless min_price || max_price

        lower = min_price || max_price
        upper = max_price || min_price

        if lower == upper
          "#{format_price_decimal(lower)} EUR"
        else
          "#{format_price_decimal(lower)} - #{format_price_decimal(upper)} EUR"
        end
      end

      def first_non_blank(*values)
        values.map { |value| value.to_s.strip }.find(&:present?).to_s
      end

      def format_price_decimal(decimal_value)
        format("%.2f", decimal_value).tr(".", ",")
      end

      def format_price_range(min_price, max_price, currency: "EUR")
        min_decimal = normalize_decimal(min_price)
        max_decimal = normalize_decimal(max_price)
        return nil if min_decimal.nil? && max_decimal.nil?

        min_decimal ||= max_decimal
        max_decimal ||= min_decimal

        if min_decimal == max_decimal
          "#{format_price_decimal(min_decimal)} #{currency}"
        else
          "#{format_price_decimal(min_decimal)} - #{format_price_decimal(max_decimal)} #{currency}"
        end
      end

      def normalize_decimal(value)
        return value if value.is_a?(BigDecimal)

        parse_price_decimal(value)
      end

      def normalize_import_description(value)
        text = value.to_s
        return nil if text.strip.blank?

        normalized =
          CGI.unescapeHTML(text)
            .gsub(/<\s*br\s*\/?>/i, "\n")
            .gsub(/<\/p\s*>/i, "\n\n")
            .gsub(/<[^>]+>/, "")
            .gsub(/\r\n?/, "\n")
            .gsub(/[ \t]+\n/, "\n")
            .gsub(/\n{3,}/, "\n\n")
            .strip

        normalized.presence
      end

      def raw_dump_payload_for(record)
        record.dump_payload.is_a?(Hash) ? record.dump_payload : {}
      end
    end
  end
end
