module Merging
  class SyncFromImports
    module RecordBuilders
      class Reservix < Base
        private

        def projection
          @projection ||= Importing::Reservix::PayloadProjection.new(event_payload: payload)
        end

        def projected_attributes
          @projected_attributes ||= projection.to_attributes || {}
        end

        def external_event_id
          projected_attributes[:external_event_id].to_s.strip.presence ||
            payload["id"].to_s.strip.presence ||
            source_identifier
        end

        def artist_name
          projected_attributes[:artist_name].to_s.strip.presence || title
        end

        def title
          projected_attributes[:title].to_s.strip
        end

        def start_at
          date = projected_attributes[:concert_date]
          return nil if date.nil?

          combine_date_and_time(date, payload["starttime"].to_s.strip)
        end

        def doors_at
          combine_date_and_time(
            start_at&.to_date,
            first_value_for_keys(%w[doors doorsat doors_at doorsopen doors_open entrytime entry_time])
          )
        end

        def city
          projected_attributes[:city].to_s.strip
        end

        def venue
          projected_attributes[:venue_name].to_s.strip
        end

        def promoter_id
          first_value_for_keys(%w[promoterid promoter_id organizerid organizer_id organizer])
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
          normalize_import_description(
            payload["description"].to_s.strip.presence ||
            first_value_for_keys(%w[text info])
          )
        end

        def min_price
          projected_attributes[:min_price]
        end

        def max_price
          projected_attributes[:max_price]
        end

        def images
          import_images_from_candidates(projection.image_candidates)
        end

        def genre
          first_value_for_keys(%w[genre genres category subcategory])
        end

        def ticket_url
          projected_attributes[:ticket_url].to_s.strip
        end

        def ticket_price_text
          format_price_range(min_price, max_price)
        end
      end
    end
  end
end
