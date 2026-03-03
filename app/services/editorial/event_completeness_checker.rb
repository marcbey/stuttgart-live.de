module Editorial
  class EventCompletenessChecker
    Result = Data.define(:score, :flags, :ready_for_publish?)

    def initialize(event:, offers: nil)
      @event = event
      @offers = Array(offers || event.event_offers)
    end

    def call
      flags = []
      flags << "missing_title" if event.title.blank?
      flags << "missing_artist" if event.artist_name.blank?
      flags << "missing_start_at" if event.start_at.blank?
      flags << "missing_venue" if event.venue.blank?
      flags << "missing_city" if event.city.blank?
      flags << "missing_image" if event.image_url.blank?
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

    attr_reader :event, :offers

    def genre_present?
      event.genre_ids.any?
    end

    def ticket_url_present?
      offers.any? do |offer|
        ticket_url = offer.respond_to?(:ticket_url) ? offer.ticket_url : offer[:ticket_url]
        sold_out = offer.respond_to?(:sold_out?) ? offer.sold_out? : ActiveModel::Type::Boolean.new.cast(offer[:sold_out])
        ticket_url.present? && !sold_out
      end
    end
  end
end
