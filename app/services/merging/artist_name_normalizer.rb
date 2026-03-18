module Merging
  module ArtistNameNormalizer
    SUPPORT_SUFFIX_PATTERN = /
      (?:
        \b(?:support|supports)\b |
        \b(?:special\s+guest|special\s+guests)\b |
        \b(?:presented\s+by|pres\.\s*by)\b |
        \b(?:live(?:\s+\d{4})?)\b |
        \b(?:on\s+tour|tour(?:\s+\d{4})?)\b
      )
    /ix.freeze

    GENERIC_TOKENS = %w[
      and
      band
      chor
      choir
      concert
      das
      der
      die
      ein
      eine
      ensemble
      koncert
      konzert
      orchester
      orchestra
      quartet
      quintet
      the
      trio
      und
    ].freeze

    module_function

    def normalize(value)
      canonical_text(value).gsub(/[^a-z0-9]/, "")
    end

    def normalize_with_fallback(*values)
      values.each do |value|
        normalized = normalize(value)
        return normalized if normalized.present?
      end

      ""
    end

    def canonical_text(value)
      normalized = I18n.transliterate(value.to_s).downcase
      normalized = normalized.tr("&", " ")
      normalized = normalized.gsub(/\bfeat(?:uring)?\b.*\z/i, " ")
      normalized = normalized.gsub(/\bft\.\b.*\z/i, " ")
      normalized = strip_support_suffixes(normalized)
      normalized.gsub(/[^a-z0-9]+/, " ").strip
    end

    def significant_tokens(value)
      canonical_text(value)
        .split
        .reject { |token| GENERIC_TOKENS.include?(token) }
    end

    def strip_support_suffixes(value)
      normalized = value.dup

      loop do
        updated = normalized.gsub(/\s*(?:[-,:+]|(?:\(|\[))?\s*#{SUPPORT_SUFFIX_PATTERN}\s*(?:\)|\])?\s*\z/, "")
        break normalized if updated == normalized

        normalized = updated.strip
      end
    end
  end
end
