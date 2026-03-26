module Public
  module Events
    module SearchQueryNormalizer
      UMLAUT_EQUIVALENTS = {
        "Ä" => "Ae",
        "Ö" => "Oe",
        "Ü" => "Ue",
        "ä" => "ae",
        "ö" => "oe",
        "ü" => "ue",
        "ß" => "ss"
      }.freeze

      module_function

      def normalize(value)
        normalized = replace_umlaut_equivalents(value.to_s)
        normalized = I18n.transliterate(normalized).downcase
        normalized.gsub(/[^a-z0-9]+/, " ").squish
      end

      def wildcard_patterns(value)
        normalized = normalize(value)
        return [] if normalized.blank?

        token_variants = normalized.split.map { |token| [ token, restore_umlauts(token) ].uniq }
        token_variants
          .reduce([ [] ]) do |combinations, variants|
            combinations.flat_map { |combination| variants.map { |variant| combination + [ variant ] } }.take(16)
          end
          .map { |tokens| "%#{tokens.join("%")}%" }
          .uniq
      end

      def replace_umlaut_equivalents(value)
        value.gsub(/[ÄÖÜäöüß]/, UMLAUT_EQUIVALENTS)
      end
      private_class_method :replace_umlaut_equivalents

      def restore_umlauts(value)
        value
          .gsub("ae", "ä")
          .gsub("oe", "ö")
          .gsub("ue", "ü")
          .gsub("ss", "ß")
      end
      private_class_method :restore_umlauts
    end
  end
end
