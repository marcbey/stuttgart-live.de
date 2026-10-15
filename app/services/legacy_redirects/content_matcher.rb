module LegacyRedirects
  class ContentMatcher
    MAX_CANDIDATES = 20
    def initialize(rule)
      @rule = rule
      @metadata = rule.source_metadata
    end

    def call
      return genre_match if rule.source_kind == "genre"
      return if metadata["title"].blank? || metadata["content"].blank?

      Matcher.choose(candidates.filter_map do |record|
        next unless Text.compatible_years?(metadata["title"], record.title)
        next unless Text.compatible_years?(metadata["content"], record.body.to_plain_text)
        next unless Text.compatible_numbers?(metadata["title"], record.title)
        next unless Text.compatible_editions?([ metadata["title"], metadata["content"] ].join(" "), [ record.title, record.body.to_plain_text ].join(" "))
        next unless Text.compatible_content?(metadata["content"], record.body.to_plain_text)
        next unless publication_matches?(record)

        Matcher::Match.new(record, nil, "content_similarity", Text.similarity(metadata["title"], record.title))
      end)
    end

    private

    attr_reader :rule, :metadata

    def candidates
      scope = rule.source_kind == "news" ? BlogPost.published_live : StaticPage.all
      label = metadata["title"].to_s.downcase
      ids = scope.where("LOWER(title) % ?", label).limit(MAX_CANDIDATES + 1).pluck(:id)
      return [] if ids.size > MAX_CANDIDATES

      scope.where(id: ids).with_rich_text_body.to_a
    end

    def genre_match
      slug = rule.source_path.delete_prefix("/genre/")
      genre = Genre.find_by(slug: slug)
      return unless genre && Public::Events::LaneDirectory.routeable_genre_slug?(genre.slug)

      Matcher::Match.new(genre, nil, "genre_slug", 1.0)
    end

    def publication_matches?(record)
      return true unless record.is_a?(BlogPost) && metadata["published_at"].present?

      Time.iso8601(metadata["published_at"]).in_time_zone.to_date == record.published_at.in_time_zone.to_date
    rescue ArgumentError
      false
    end
  end
end
