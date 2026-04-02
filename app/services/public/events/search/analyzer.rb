module Public
  module Events
    module Search
      class Analyzer
        Suggestion = Data.define(:label, :query, :submit)
        Result = Data.define(
          :raw_query,
          :canonical_query,
          :state,
          :resolution,
          :venue_glue,
          :venue_query,
          :suggestions
        ) do
          def blank?
            state == :blank
          end

          def time_incomplete?
            state == :time_incomplete
          end

          def time_complete?
            state == :time_complete
          end

          def venue_fragment?
            state == :venue_fragment
          end

          def fallback_text?
            state == :fallback_text
          end

          def structured?
            resolution.present?
          end

          def ready_for_event_search?
            structured? && (time_complete? || venue_fragment?)
          end

          def venue_search?
            venue_fragment? && venue_query.present?
          end
        end

        GLUES = [
          { canonical: "in der", label: "in der" },
          { canonical: "in dem", label: "in dem" },
          { canonical: "im", label: "im" },
          { canonical: "in", label: "in" }
        ].freeze

        def self.call(query)
          new(query).call
        end

        def initialize(query)
          @raw_query = query.to_s.strip
          @canonical_query = Normalizer.normalize_parser(@raw_query)
        end

        def call
          return blank_result if canonical_query.blank?

          static_result ||
            weekday_result ||
            month_result ||
            date_result ||
            fallback_result
        end

        private

        attr_reader :raw_query, :canonical_query

        def blank_result
          Result.new(raw_query:, canonical_query:, state: :blank, resolution: nil, venue_glue: nil, venue_query: nil, suggestions: [])
        end

        def fallback_result
          Result.new(raw_query:, canonical_query:, state: :fallback_text, resolution: nil, venue_glue: nil, venue_query: nil, suggestions: [])
        end

        def static_result
          Public::Events::Search::TimePhraseResolver::STATIC_PHRASES.each do |canonical_phrase, config|
            result = match_resolution(
              canonical_phrase:,
              resolution_type: config.fetch(:type),
              label: config.fetch(:label)
            )
            return result if result.present?
          end

          nil
        end

        def weekday_result
          match = canonical_query.match(/\A(diesen|naechsten)(?:\s+(.*))?\z/)
          return unless match

          prefix = match[1]
          fragment = match[2].to_s.strip
          return incomplete_result(suggestions: relative_period_suggestions(prefix:, fragment: "")) if fragment.blank?

          if fragment == "monat" || fragment.start_with?("monat ")
            resolution_type = prefix == "diesen" ? :this_month : :next_month
            resolution = TimePhraseResolver.resolve(type: resolution_type)
            remainder = fragment.delete_prefix("monat").strip
            return maybe_match_venue_tail(resolution, remainder:)
          end

          TimePhraseResolver.full_weekday_names.each do |weekday_key, name|
            canonical_name = Normalizer.normalize_parser(name)

            if fragment == canonical_name || fragment.start_with?("#{canonical_name} ")
              resolution_type = prefix == "diesen" ? :this_weekday : :next_weekday
              resolution = TimePhraseResolver.resolve(type: resolution_type, value: weekday_key)
              remainder = fragment.delete_prefix(canonical_name).strip
              return maybe_match_venue_tail(resolution, remainder:)
            end
          end

          suggestions = relative_period_suggestions(prefix:, fragment:)
          incomplete_result(suggestions:) if suggestions.any?
        end

        def month_result
          match = canonical_query.match(/\Aim(?:\s+(.*))?\z/)
          return unless match

          fragment = match[1].to_s.strip
          return incomplete_result(suggestions: month_suggestions(fragment: "")) if fragment.blank?

          TimePhraseResolver.full_month_names.each do |month_key, name|
            canonical_name = Normalizer.normalize_parser(name)

            if fragment == canonical_name || fragment.start_with?("#{canonical_name} ")
              resolution = TimePhraseResolver.resolve(type: :month, value: month_key)
              remainder = fragment.delete_prefix(canonical_name).strip
              return maybe_match_venue_tail(resolution, remainder:)
            end
          end

          suggestions = month_suggestions(fragment:)
          incomplete_result(suggestions:) if suggestions.any?
        end

        def date_result
          match = canonical_query.match(/\Aam(?:\s+(.*))?\z/)
          return unless match

          fragment = match[1].to_s.strip
          return incomplete_result(suggestions: []) if fragment.blank?

          date_match = fragment.match(/\A(\d{1,2}\.\d{1,2}\.(?:\d{4})?)(?:\s+(.*))?\z/)
          if date_match.present?
            resolution = TimePhraseResolver.resolve(type: :date, value: date_match[1])
            return maybe_match_venue_tail(resolution, remainder: date_match[2].to_s.strip)
          end

          return incomplete_result(suggestions: []) if fragment.match?(/\A\d{1,2}(?:\.\d{0,2}(?:\.\d{0,4})?)?\z/)

          nil
        end

        def match_resolution(canonical_phrase:, resolution_type:, label:)
          return incomplete_result(suggestions: [ Suggestion.new(label:, query: label, submit: false) ]) if phrase_prefix?(canonical_phrase)
          return unless exact_or_prefixed_phrase_match?(canonical_phrase)

          resolution = TimePhraseResolver.resolve(type: resolution_type)
          remainder = canonical_query.delete_prefix(canonical_phrase).strip
          maybe_match_venue_tail(resolution, remainder:)
        end

        def maybe_match_venue_tail(resolution, remainder:)
          return time_complete_result(resolution:) if remainder.blank?

          matched_glue = matching_glue(remainder)
          return incomplete_result(suggestions: glue_suggestions_for(resolution:, fragment: remainder)) if matched_glue.blank?

          venue_query = remainder.delete_prefix(matched_glue.fetch(:canonical)).strip
          return incomplete_result(suggestions: glue_suggestion(resolution:, glue: matched_glue)) if venue_query.blank?

          Result.new(
            raw_query:,
            canonical_query:,
            state: :venue_fragment,
            resolution:,
            venue_glue: matched_glue.fetch(:label),
            venue_query:,
            suggestions: []
          )
        end

        def time_complete_result(resolution:)
          Result.new(
            raw_query:,
            canonical_query:,
            state: :time_complete,
            resolution:,
            venue_glue: nil,
            venue_query: nil,
            suggestions: glue_suggestion(resolution:, glue: GLUES.third)
          )
        end

        def incomplete_result(suggestions:)
          Result.new(
            raw_query:,
            canonical_query:,
            state: :time_incomplete,
            resolution: nil,
            venue_glue: nil,
            venue_query: nil,
            suggestions:
          )
        end

        def phrase_prefix?(canonical_phrase)
          canonical_phrase.start_with?(canonical_query) && canonical_query != canonical_phrase
        end

        def exact_phrase_match?(canonical_phrase)
          canonical_query == canonical_phrase
        end

        def exact_or_prefixed_phrase_match?(canonical_phrase)
          exact_phrase_match?(canonical_phrase) || canonical_query.start_with?("#{canonical_phrase} ")
        end

        def weekday_suggestions(prefix:, fragment:)
          TimePhraseResolver.full_weekday_names.filter_map do |weekday_key, name|
            canonical_name = Normalizer.normalize_parser(name)
            next unless canonical_name.start_with?(fragment)

            label_prefix = prefix == "diesen" ? "Diesen" : "Nächsten"
            Suggestion.new(label: "#{label_prefix} #{name}", query: "#{label_prefix} #{name}", submit: false)
          end
        end

        def relative_period_suggestions(prefix:, fragment:)
          suggestions = weekday_suggestions(prefix:, fragment:)
          if "monat".start_with?(fragment)
            label = prefix == "diesen" ? "Diesen Monat" : "Nächsten Monat"
            suggestions.unshift(Suggestion.new(label:, query: label, submit: false))
          end

          suggestions
        end

        def month_suggestions(fragment:)
          TimePhraseResolver.full_month_names.filter_map do |month_key, name|
            canonical_name = Normalizer.normalize_parser(name)
            next unless canonical_name.start_with?(fragment)

            Suggestion.new(label: "Im #{name}", query: "Im #{name}", submit: false)
          end
        end
        def matching_glue(remainder)
          GLUES.find { |glue| remainder == glue.fetch(:canonical) || remainder.start_with?("#{glue.fetch(:canonical)} ") }
        end

        def glue_suggestions_for(resolution:, fragment:)
          GLUES.filter_map do |glue|
            next unless glue.fetch(:canonical).start_with?(fragment)

            Suggestion.new(
              label: "#{resolution.label} #{glue.fetch(:label)}",
              query: "#{resolution.label} #{glue.fetch(:label)}",
              submit: false
            )
          end
        end

        def glue_suggestion(resolution:, glue:)
          [
            Suggestion.new(
              label: "#{resolution.label} #{glue.fetch(:label)}",
              query: "#{resolution.label} #{glue.fetch(:label)}",
              submit: false
            )
          ]
        end
      end
    end
  end
end
