module Importing
  module LocationMatcherSupport
    def initialize(location_whitelist)
      @location_whitelist = normalize_values(location_whitelist)
    end

    def match?(payload)
      return true if location_whitelist.empty?

      location_candidates(payload).any? do |candidate|
        location_whitelist.any? do |allowed|
          candidate.include?(allowed) || allowed.include?(candidate)
        end
      end
    end

    private

    attr_reader :location_whitelist

    def normalize_values(values)
      Array(values)
        .map { |value| normalize(value.to_s) }
        .reject(&:blank?)
        .uniq
    end

    def normalize(value)
      I18n.transliterate(value)
        .downcase
        .gsub(/[^a-z0-9]+/, " ")
        .squeeze(" ")
        .strip
    end

    def normalize_key(value)
      I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]/, "")
    end
  end
end
