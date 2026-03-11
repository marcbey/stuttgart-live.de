require "cgi"
require "bigdecimal"
require "set"

module Merging
  class SyncFromImports
    Result = Data.define(
      :import_records_count,
      :groups_count,
      :events_created_count,
      :events_updated_count,
      :offers_upserted_count
    )

    ImportRecord = Data.define(
      :source,
      :external_event_id,
      :concert_date,
      :begin_time,
      :city,
      :venue_name,
      :title,
      :artist_name,
      :promoter_id,
      :description_text,
      :ticket_url,
      :ticket_price_text,
      :min_price,
      :max_price,
      :images,
      :raw_payload
    )

    ImportImage = Data.define(
      :source,
      :image_type,
      :image_url,
      :role,
      :aspect_hint,
      :position
    )

    def initialize(merge_run_id: nil, logger: Rails.logger)
      @merge_run_id = merge_run_id
      @logger = logger
      @priority_map = ProviderPriorityMap.call
    end

    def call
      records = import_records
      groups = records.group_by { |record| fingerprint_for(record) }

      created = 0
      updated = 0
      offers_upserted = 0

      ActiveRecord::Base.transaction do
        groups.each_value do |records|
          ordered_records = ordered_records_for_group(records)
          event, created_now, updated_now, offers_count = upsert_event_for(ordered_records)
          created += 1 if created_now
          updated += 1 if updated_now
          offers_upserted += offers_count

          logger.info("[Merging::SyncFromImports] synced event ##{event.id} with #{ordered_records.size} source records")
        end
      end

      Result.new(
        import_records_count: records.size,
        groups_count: groups.count,
        events_created_count: created,
        events_updated_count: updated,
        offers_upserted_count: offers_upserted
      )
    end

    private

    attr_reader :merge_run_id, :logger, :priority_map

    def import_records
      easyticket_records + eventim_records + reservix_records
    end

    def easyticket_records
      EasyticketImportEvent
        .active
        .includes(:import_event_images)
        .joins(:import_source)
        .where(import_sources: { active: true, source_type: "easyticket" })
        .map do |record|
          ensure_import_record_images!(record, source: "easyticket")

          ImportRecord.new(
            source: "easyticket",
            external_event_id: record.external_event_id,
            concert_date: record.concert_date,
            begin_time: begin_time_for_easyticket(record),
            city: record.city,
            venue_name: record.venue_name,
            title: record.title,
            artist_name: record.artist_name,
            promoter_id: promoter_id_for_easyticket(record),
            description_text: description_text_for_easyticket(record),
            ticket_url: record.ticket_url,
            ticket_price_text: ticket_price_text_for_easyticket(record),
            min_price: nil,
            max_price: nil,
            images: images_for_import_record(record, fallback_source: "easyticket"),
            raw_payload: {
              dump_payload: record.dump_payload,
              detail_payload: record.detail_payload
            }
          )
        end
    end

    def eventim_records
      EventimImportEvent
        .active
        .includes(:import_event_images)
        .joins(:import_source)
        .where(import_sources: { active: true, source_type: "eventim" })
        .map do |record|
          ensure_import_record_images!(record, source: "eventim")

          ImportRecord.new(
            source: "eventim",
            external_event_id: record.external_event_id,
            concert_date: record.concert_date,
            begin_time: begin_time_for_eventim(record),
            city: record.city,
            venue_name: record.venue_name,
            title: record.title,
            artist_name: record.artist_name,
            promoter_id: promoter_id_for_eventim(record),
            description_text: description_text_for_eventim(record),
            ticket_url: record.ticket_url,
            ticket_price_text: ticket_price_text_for_eventim(record),
            min_price: nil,
            max_price: nil,
            images: images_for_import_record(record, fallback_source: "eventim"),
            raw_payload: {
              dump_payload: record.dump_payload,
              detail_payload: record.detail_payload
            }
          )
        end
    end

    def reservix_records
      ReservixImportEvent
        .active
        .includes(:import_event_images)
        .joins(:import_source)
        .where(import_sources: { active: true, source_type: "reservix" })
        .map do |record|
          ensure_import_record_images!(record, source: "reservix")

          ImportRecord.new(
            source: "reservix",
            external_event_id: record.external_event_id,
            concert_date: record.concert_date,
            begin_time: begin_time_for_reservix(record),
            city: record.city,
            venue_name: record.venue_name,
            title: record.title,
            artist_name: record.artist_name,
            promoter_id: nil,
            description_text: description_text_for_reservix(record),
            ticket_url: record.ticket_url,
            ticket_price_text: ticket_price_text_for_reservix(record),
            min_price: record.min_price,
            max_price: record.max_price,
            images: images_for_import_record(record, fallback_source: "reservix"),
            raw_payload: {
              dump_payload: record.dump_payload,
              detail_payload: record.detail_payload
            }
          )
        end
    end

    def upsert_event_for(records)
      primary = records.first
      fingerprint = fingerprint_for(primary)

      event = Event.find_or_initialize_by(source_fingerprint: fingerprint)
      created_now = event.new_record?

      event.title = first_present(records, &:title)
      event.artist_name = first_present(records, &:artist_name)
      event.city = first_present(records, &:city)
      event.venue = first_present(records, &:venue_name)
      event.promoter_id = first_present(records, &:promoter_id).presence
      event.min_price = first_present_decimal(records, &:min_price)
      event.max_price = first_present_decimal(records, &:max_price)
      imported_description_text = first_present_or_nil(records, &:description_text)
      event.event_info = imported_description_text if imported_description_text.present?
      event.start_at = start_at_for(primary.concert_date, primary.begin_time)
      event.primary_source = primary.source
      event.source_snapshot = build_source_snapshot(records)
      updated_now = event.changed?

      merged_images = merged_image_candidates(records)
      offers = build_offer_attributes(records)
      images_present = merged_images.any?
      completeness = Editorial::EventCompletenessChecker.new(event: event, offers: offers, images_present: images_present).call
      event.completeness_score = completeness.score
      event.completeness_flags = completeness.flags

      apply_status_rules(event, completeness, images_present: images_present)
      updated_now ||= event.changed?
      event.save! if created_now || updated_now

      offers_upserted = sync_offers!(event, offers)
      images_changed = sync_event_images!(event, merged_images)

      effective_updated = (updated_now || images_changed) && !created_now

      if created_now || effective_updated
        Editorial::EventChangeLogger.log!(
          event: event,
          action: created_now ? "merged_create" : "merged_update",
          user: nil,
          metadata: merge_change_metadata(records)
        )
      end

      [ event, created_now, effective_updated, offers_upserted ]
    end

    def apply_status_rules(event, completeness, images_present:)
      return if event.status == "rejected"
      return if event.published? && !event.auto_published?

      if completeness.ready_for_publish? && images_present
        event.status = "published"
        event.auto_published = true
        event.sync_publication_fields
      else
        event.status = "needs_review"
        event.auto_published = false
        event.published_at = nil if event.published_by_id.nil?
      end
    end

    def sync_offers!(event, offers)
      existing = event.event_offers.index_by { |offer| [ offer.source, offer.source_event_id ] }
      upserted = 0

      offers.each do |attrs|
        key = [ attrs[:source], attrs[:source_event_id] ]
        offer = existing.delete(key) || event.event_offers.new
        offer.assign_attributes(attrs)
        next unless offer.new_record? || offer.changed?

        offer.save!
        upserted += 1
      end

      existing.each_value(&:destroy!)
      upserted
    end

    def build_offer_attributes(records)
      records.map do |record|
        {
          source: record.source,
          source_event_id: record.external_event_id,
          ticket_url: record.ticket_url,
          ticket_price_text: record.ticket_price_text,
          sold_out: false,
          priority_rank: priority_for(record.source),
          metadata: build_offer_metadata(record)
        }
      end
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

    def merged_image_candidates(records)
      candidates = []
      seen = Set.new

      records
        .flat_map(&:images)
        .sort_by { |image| [ priority_for(image.source), image.position.to_i, image.image_type.to_s ] }
        .each do |image|
          key = image_key(source: image.source, image_type: image.image_type, image_url: image.image_url)
          next if seen.include?(key)

          seen << key
          candidates << {
            source: image.source,
            image_type: image.image_type,
            image_url: image.image_url,
            role: image.role,
            aspect_hint: image.aspect_hint,
            position: candidates.length
          }
        end

      candidates
    end

    def sync_event_images!(event, candidates)
      Importing::ImportEventImagesSync.call(owner: event, candidates: candidates)
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

    def start_at_for(concert_date, begin_time)
      hour, min = parse_time_components(begin_time)
      Time.zone.local(concert_date.year, concert_date.month, concert_date.day, hour, min, 0)
    end

    def parse_time_components(value)
      raw = value.to_s.strip
      match = raw.match(/(?<!\d)(\d{1,2})[:.](\d{2})(?!\d)/)
      if match.present?
        hour = match[1].to_i
        min = match[2].to_i
        return [ hour, min ] if hour.between?(0, 23) && min.between?(0, 59)
      end

      fallback_hour = 20
      fallback_min = 0
      [ fallback_hour, fallback_min ]
    end

    def ordered_records_for_group(records)
      records.sort_by do |record|
        [
          priority_for(record.source),
          record.source.to_s,
          record.external_event_id.to_s
        ]
      end
    end

    def fingerprint_for(record)
      [
        normalize_token(record.artist_name),
        normalize_token(record.venue_name),
        record.concert_date.iso8601
      ].join("::")
    end

    def normalize_token(value)
      I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]/, "")
    end

    def build_source_snapshot(records)
      {
        "sources" =>
          records.map do |record|
            {
              "source" => record.source,
              "external_event_id" => record.external_event_id,
              "concert_date" => record.concert_date.iso8601,
              "begin_time" => record.begin_time,
              "city" => record.city,
              "venue_name" => record.venue_name,
              "title" => record.title,
              "artist_name" => record.artist_name,
              "promoter_id" => record.promoter_id,
              "description_text" => record.description_text,
              "ticket_url" => record.ticket_url,
              "ticket_price_text" => record.ticket_price_text,
              "min_price" => decimal_as_json(record.min_price),
              "max_price" => decimal_as_json(record.max_price),
              "images" =>
                record.images.map do |image|
                  {
                    "source" => image.source,
                    "image_type" => image.image_type,
                    "image_url" => image.image_url,
                    "role" => image.role,
                    "aspect_hint" => image.aspect_hint,
                    "position" => image.position
                  }
                end,
              "raw_payload" => record.raw_payload
            }
          end
      }
    end

    def first_present(records)
      records.each do |record|
        value = yield(record).to_s.strip
        return value if value.present?
      end

      ""
    end

    def first_present_or_nil(records)
      records.each do |record|
        value = yield(record).to_s.strip
        return value if value.present?
      end

      nil
    end

    def first_present_decimal(records)
      records.each do |record|
        value = yield(record)
        decimal = normalize_decimal(value)
        return decimal if decimal.present?
      end

      nil
    end

    def priority_for(source)
      priority_map.fetch(source, 999)
    end

    def build_offer_metadata(record)
      metadata = {}

      min_price = decimal_as_json(record.min_price)
      max_price = decimal_as_json(record.max_price)
      metadata["min_price"] = min_price if min_price.present?
      metadata["max_price"] = max_price if max_price.present?

      metadata
    end

    def decimal_as_json(value)
      decimal = normalize_decimal(value)
      return nil if decimal.nil?

      decimal.to_s("F")
    end

    def image_key(source:, image_type:, image_url:)
      [
        source.to_s.strip.downcase,
        image_type.to_s.strip,
        image_url.to_s.strip.downcase
      ]
    end

    def merge_change_metadata(records)
      {
        source_types: records.map(&:source).uniq,
        external_event_ids: records.map(&:external_event_id),
        merge_run_id: merge_run_id
      }.compact
    end
  end
end
