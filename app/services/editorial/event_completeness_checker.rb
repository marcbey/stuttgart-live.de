module Editorial
  class EventCompletenessChecker
    Result = Data.define(:score, :flags, :ready_for_publish?)

    def initialize(event:, offers: nil, images_present: nil)
      @event = event
      @offers = Array(offers || event.event_offers)
      @images_present = images_present
    end

    def call
      flags = []
      flags << "missing_title" if event.title.blank?
      flags << "missing_artist" if event.artist_name.blank?
      flags << "missing_start_at" if event.start_at.blank?
      flags << "missing_venue" if event.venue.blank?
      flags << "missing_city" if event.city.blank?
      flags << "missing_image" unless image_present?
      flags << "missing_ticket_url" unless ticket_url_present?
      flags << "missing_genre" unless genre_present?

      score = ((REQUIRED_FIELDS_COUNT - flags.count).to_f / REQUIRED_FIELDS_COUNT * 100).round
      ready = (flags & BLOCKING_FLAGS).empty?

      Result.new(score: score, flags: flags, ready_for_publish?: ready)
    end

    private

    REQUIRED_FIELDS_COUNT = 8
    BLOCKING_FLAGS = %w[
      missing_title
      missing_artist
      missing_start_at
      missing_venue
      missing_city
      missing_image
      missing_ticket_url
    ].freeze

    attr_reader :event, :offers, :images_present

    def genre_present?
      event.genre_ids.any?
    end

    def image_present?
      return ActiveModel::Type::Boolean.new.cast(images_present) unless images_present.nil?
      has_import_images = image_association_present?(event, :import_event_images)
      has_editorial_images = image_association_present?(event, :event_images)

      has_import_images || has_editorial_images
    end

    def image_association_present?(record, association_name)
      return false unless record.respond_to?(association_name)

      association = record.public_send(association_name)
      association.loaded? ? association.any? : association.exists?
    end

    def ticket_url_present?
      offers.any? do |offer|
        ticket_url =
          if offer.respond_to?(:resolved_ticket_url)
            offer.resolved_ticket_url
          else
            EventOffer.resolve_ticket_url(
              extract_offer_value(offer, :ticket_url),
              extract_offer_value(offer, :source_event_id)
            )
          end
        sold_out =
          if offer.respond_to?(:sold_out?)
            offer.sold_out?
          else
            ActiveModel::Type::Boolean.new.cast(extract_offer_value(offer, :sold_out))
          end
        ticket_url.present? && !sold_out
      end
    end

    def extract_offer_value(offer, key)
      return offer.public_send(key) if offer.respond_to?(key)

      offer[key] || offer[key.to_s]
    end
  end
end
