module LegacyRedirects
  class EventMatcher
    MAX_CANDIDATES = 100
    def initialize(rule)
      @rule = rule
      @metadata = rule.source_metadata
    end

    def call
      identity = provider_match
      return identity if identity

      dates = date_matches
      return if @overflow

      Matcher.choose(dates) || series_match
    end

    private

    attr_reader :rule, :metadata

    def provider_match
      ids = Array(metadata["provider_ids"]).filter_map do |reference|
        next unless reference.is_a?(Hash) && reference["source"].present? && reference["id"].present?

        offers = EventOffer.where(source: reference["source"], source_event_id: reference["id"].to_s).pluck(:event_id)
        if offers.empty?
          source = { "source" => reference["source"], "external_event_id" => reference["id"].to_s }
          offers = Event.where("source_snapshot @> ?::jsonb", { sources: [ source ] }.to_json).pluck(:id)
        end
        offers
      end.flatten.uniq
      matches = Event.published_live.where(id: ids).limit(2).to_a
      return unless matches.one?

      Matcher::Match.new(matches.first, nil, "provider_id", 1.0)
    end

    def date_matches
      dates = date_references
      return [] if dates.empty? || metadata["venue"].blank?

      scopes = dates.filter_map do |reference|
        date = Date.iso8601(reference.fetch("date"))
        Event.published_live.where(start_at: date.in_time_zone.all_day)
      rescue Date::Error, KeyError
        nil
      end
      return [] if scopes.empty?

      ids = scopes.reduce(&:or).limit(MAX_CANDIDATES + 1).pluck(:id)
      if ids.size > MAX_CANDIDATES
        @overflow = true
        return []
      end

      Event.published_live.where(id: ids).includes(:venue_record).filter_map do |event|
        next unless matching_venue?(event) && matching_time?(event, dates)

        match_for(event, "event_identity")
      end
    end

    def series_match
      return if production.blank? || metadata["venue"].blank? || metadata["artist_name"].blank?

      label = metadata["artist_name"].to_s.downcase
      candidates = Event.published_live.where.not(event_series_id: nil)
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .where("LOWER(artist_name) % ?", label)
      ids = candidates.limit(MAX_CANDIDATES + 1).pluck(:id)
      return if ids.size > MAX_CANDIDATES

      candidates = candidates.where(id: ids).includes(:venue_record).to_a
      matches = candidates.group_by(&:event_series_id).values.filter_map do |events|
        production_matches = events.filter_map { |event| match_for(event, "event_series") }
          .select { |match| match.score >= Matcher::MIN_SCORE }
        next if production_matches.size < 2

        compatible = production_matches.select { |match| matching_venue?(match.target) }
        next if compatible.empty?

        compatible.min_by { |match| [ match.target.start_at, match.target.id ] }
      end
      Matcher.choose(matches)
    end

    def match_for(event, reason)
      artist = metadata["artist_name"].presence
      title = production.presence
      return if artist.blank? && title.blank?
      return unless Text.compatible_years?(title, event.title)
      return unless Text.compatible_numbers?(title, event.title)
      return unless Text.compatible_editions?(title, event.title)

      values = []
      values << Text.similarity(artist, event.artist_name) if artist
      values << Text.similarity(title, event.title) if title
      score = values.min
      Matcher::Match.new(event, nil, reason, score)
    end

    def production
      explicit = metadata["production"].presence
      return explicit if explicit && Text.normalize(explicit) != Text.normalize(metadata["artist_name"])

      title = metadata["title"].presence
      title if title && Text.normalize(title) != Text.normalize(metadata["artist_name"])
    end

    def matching_venue?(event)
      Venue.canonical_match_key(metadata["venue"]) == Venue.canonical_match_key(event.venue)
    end

    def date_references
      references = Array(metadata["dates"]).select { |value| value.is_a?(Hash) }
      references = [ metadata.slice("date", "start_at", "time_known") ] if references.empty? && metadata["date"].present?
      references
    end

    def matching_time?(event, dates)
      dates.any? do |reference|
        next false unless reference["date"] == event.start_at.in_time_zone.to_date.iso8601
        next true unless reference["time_known"] && reference["start_at"].present?

        event.start_at.to_i / 60 == Time.iso8601(reference["start_at"]).to_i / 60
      rescue ArgumentError
        false
      end
    end
  end
end
