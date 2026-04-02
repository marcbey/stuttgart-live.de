module Public
  module Events
    module SearchQueryNormalizer
      module_function

      def normalize(value)
        Public::Events::Search::Normalizer.normalize(value)
      end

      def wildcard_patterns(value)
        Public::Events::Search::Normalizer.wildcard_patterns(value)
      end

      def normalize_parser(value)
        Public::Events::Search::Normalizer.normalize_parser(value)
      end

      def compact_normalize(value)
        Public::Events::Search::Normalizer.compact_normalize(value)
      end
    end
  end
end
