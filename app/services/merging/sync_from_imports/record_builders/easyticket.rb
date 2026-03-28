module Merging
  class SyncFromImports
    module RecordBuilders
      class Easyticket < Base
        private

        def projection
          @projection ||= Importing::Easyticket::PayloadProjection.new(
            dump_payload: payload,
            detail_payload: detail_payload
          )
        end

        def projected_attributes
          @projected_attributes ||= projection.to_attributes || {}
        end

        def external_event_id
          projected_attributes[:external_event_id].to_s.strip.presence ||
            source_identifier.split(":").first.to_s.strip
        end

        def artist_name
          projected_attributes[:artist_name].to_s.strip.presence ||
            title
        end

        def title
          projected_attributes[:title].to_s.strip
        end

        def start_at
          datetime =
            parse_datetime(payload["date_time"]) ||
            parse_datetime(payload.dig("data", "event_date", "date_time"))
          return datetime if datetime.present?

          date = projected_attributes[:concert_date]
          return nil if date.nil?

          time_value =
            payload["time"].to_s.strip.presence ||
            payload.dig("data", "event_date", "time").to_s.strip.presence ||
            parse_time_from_datetime(payload["date_time"]) ||
            parse_time_from_datetime(payload.dig("data", "event_date", "date_time"))

          combine_date_and_time(date, time_value)
        end

        def doors_at
          date = start_at&.to_date
          combine_date_and_time(
            date,
            projected_attributes[:doors_time],
            fallback_time: nil
          )
        end

        def city
          projected_attributes[:city].to_s.strip.presence ||
            Importing::Easyticket::PayloadProjection.infer_city_from_location_name(
              payload["location_name"].to_s.strip.presence ||
                payload["loc_name"].to_s.strip.presence ||
                payload.dig("data", "location", "name").to_s.strip.presence
            )
        end

        def venue
          projected_attributes[:venue_name].to_s.strip.presence ||
            payload["location_name"].to_s.strip.presence ||
            payload.dig("data", "venue", "name").to_s.strip.presence ||
            payload.dig("data", "event", "venue").to_s.strip
        end

        def promoter_id
          projected_attributes[:organizer_id].to_s.strip
        end

        def badge_text
          first_value_for_keys(%w[badge badge_text label tag])
        end

        def youtube_url
          first_url_for_keys(%w[youtube youtube_url youtubeurl video videourl trailer]) ||
            first_url_for_hosts("youtube.com", "youtu.be")
        end

        def homepage_url
          first_url_for_keys(%w[homepage homepage_url homepageurl website website_url websiteurl])
        end

        def facebook_url
          first_url_for_keys(%w[facebook facebook_url facebookurl]) ||
            first_url_for_hosts("facebook.com", "fb.com")
        end

        def event_info
          text =
            [
              payload["text"],
              payload["description"],
              payload["booking_info"],
              payload["additional_info"],
              payload.dig("data", "event", "description"),
              payload.dig("data", "event", "info"),
              payload.dig("data", "event", "additional_info")
            ].map(&:to_s).reject(&:blank?).join("\n\n")

          normalize_import_description(text)
        end

        def min_price
          parse_decimal(payload["price_start"])
        end

        def max_price
          parse_decimal(payload["price_end"]) || min_price
        end

        def images
          import_images_from_candidates(projection.image_candidates)
        end

        def genre
          first_value_for_keys(%w[genre genres category subcategory])
        end

        def ticket_url
          direct = projected_attributes[:ticket_url].to_s.strip.presence
          return direct if direct.present? && direct.match?(URL_PATTERN)

          base = AppConfig.easyticket_ticket_link_event_base_url.to_s.strip
          ticket_event_id = payload["title_3"].to_s.strip.presence || external_event_id
          return nil if base.blank? || ticket_event_id.blank?

          "#{base.sub(%r{/+\z}, "")}/#{ticket_event_id}"
        end

        def ticket_price_text
          payload["price_text"].to_s.strip.presence || format_price_range(min_price, max_price)
        end

        def sold_out
          return true if ActiveModel::Type::Boolean.new.cast(payload["not_bookable"])

          availability = payload["structured_data_availability"].to_s.strip.downcase
          return false if availability.blank?

          availability.include?("soldout") ||
            availability.include?("sold_out") ||
            availability.include?("outofstock") ||
            availability.include?("out_of_stock")
        end

        def detail_payload
          raw_event_import.detail_payload.is_a?(Hash) ? raw_event_import.detail_payload.deep_stringify_keys : {}
        end
      end
    end
  end
end
