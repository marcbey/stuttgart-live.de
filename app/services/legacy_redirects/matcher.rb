module LegacyRedirects
  class Matcher
    MIN_SCORE = 0.90
    MIN_MARGIN = 0.10
    Match = Data.define(:target, :target_path, :reason, :score)
    FIXED_EQUIVALENTS = { "/events-stuttgart" => "/events", "/newsletter" => "/newsletter_subscribers/new" }.freeze

    def self.call(rule)
      new(rule).call
    end

    def self.choose(matches)
      ranked = matches.compact.sort_by { |match| -match.score }.uniq { |match| [ match.target&.class&.name, match.target&.id, match.target_path ] }
      first, second = ranked.first(2)
      return unless first && first.score >= MIN_SCORE
      return if second && (first.score - second.score).round(8) < MIN_MARGIN

      first
    end

    def initialize(rule)
      @rule = rule
    end

    def call
      case rule.source_kind
      when "event" then EventMatcher.new(rule).call
      when "news" then blog_source_match || ContentMatcher.new(rule).call
      when "page", "genre" then fixed_match || ContentMatcher.new(rule).call
      when "file" then file_match
      end
    end

    private

    attr_reader :rule

    def blog_source_match
      posts = BlogPost.published_live.where(source_url: BlogPost.source_url_candidates_for(rule.source_path)).limit(2).to_a
      return unless posts.one?

      Match.new(posts.first, nil, "blog_source_url", 1.0)
    end

    def fixed_match
      path = FIXED_EQUIVALENTS[rule.source_path]
      resolved = Target.resolve(path) if path
      return unless resolved

      Match.new(resolved[:target], resolved[:target_path], "equivalent_route", 1.0)
    end

    def file_match
      # Checksums/provenance are prepared by the inventory; never download in requests.
      checksum = rule.source_metadata["checksum"]
      return if checksum.blank?

      blobs = ActiveStorage::Blob.where(checksum: checksum).limit(10).select do |blob|
        Target.path_for(LegacyRedirect.new(target: blob)).present?
      end
      return if blobs.empty?

      Match.new(blobs.min_by(&:id), nil, "file_checksum", 1.0)
    end
  end
end
