module Events
  module ArtistTitleSanitizer
    Sanitized = Data.define(:artist_name, :title)

    NON_ARTIST_NAME_PATTERN = /
      \A[„"'].*[“”"']\s*(?:[-–—:]\s*)?
      (?:lesetour|tour|live|show|gala|abend)\b
    /ix.freeze

    module_function

    def sanitize(artist_name:, title:)
      sanitized_artist_name = artist_name.to_s.strip
      sanitized_title = title.to_s.strip

      match = sanitized_title.match(/\A(.+?)\s*[-–—]\s+(.+)\z/)
      return Sanitized.new(artist_name: sanitized_artist_name, title: sanitized_title) unless match

      extracted_artist = match[1].to_s.strip
      extracted_title = match[2].to_s.strip
      return Sanitized.new(artist_name: sanitized_artist_name, title: sanitized_title) if extracted_artist.blank? || extracted_title.blank?

      normalized_artist = normalize_comparison_token(sanitized_artist_name)
      normalized_title = normalize_comparison_token(sanitized_title)
      normalized_extracted_artist = normalize_comparison_token(extracted_artist)

      if sanitized_artist_name.blank? || normalized_artist == normalized_title || normalized_artist == normalized_extracted_artist
        Sanitized.new(artist_name: extracted_artist, title: extracted_title)
      else
        Sanitized.new(artist_name: sanitized_artist_name, title: sanitized_title)
      end
    end

    def artist_name_for_query(artist_name:, title:)
      sanitized = sanitize(artist_name:, title:)

      if use_title_for_artist_query?(artist_name: sanitized.artist_name, title: sanitized.title)
        sanitized.title
      else
        sanitized.artist_name
      end
    end

    def normalize_comparison_token(value)
      value.to_s.downcase.gsub(/[^[:alnum:]]+/, "")
    end

    def use_title_for_artist_query?(artist_name:, title:)
      artist_name.match?(NON_ARTIST_NAME_PATTERN) && title.present?
    end
  end
end
