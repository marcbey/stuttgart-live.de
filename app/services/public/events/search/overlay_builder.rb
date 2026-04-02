module Public
  module Events
    module Search
      class OverlayBuilder
        VenueSuggestion = Data.define(:name, :address, :query, :submit)
        Result = Data.define(:mode, :query, :events, :suggestions, :venues) do
          def idle?
            mode == :idle
          end

          def suggestions?
            mode == :suggestions
          end

          def venues?
            mode == :venues
          end

          def events?
            mode == :events
          end

          def parser_suggestions?
            suggestions? || venues?
          end

          def standard_events?
            events.any?
          end
        end

        def self.build(query:, idle_loader:, event_loader:, standard_event_loader:)
          new(query:, idle_loader:, event_loader:, standard_event_loader:).call
        end

        def initialize(query:, idle_loader:, event_loader:, standard_event_loader:)
          @query = query.to_s.strip
          @idle_loader = idle_loader
          @event_loader = event_loader
          @standard_event_loader = standard_event_loader
        end

        def call
          analysis = Analyzer.call(query)
          return Result.new(mode: :idle, query: nil, events: idle_loader.call, suggestions: [], venues: []) if analysis.blank?
          return Result.new(mode: :suggestions, query:, events: standard_event_loader.call, suggestions: analysis.suggestions, venues: []) if analysis.time_incomplete?

          if analysis.venue_search?
            venues = VenueSuggester.call(analysis.venue_query).map do |venue|
              VenueSuggestion.new(
                name: venue.name,
                address: venue.address.to_s.strip.presence,
                query: build_venue_query(analysis:, venue:),
                submit: true
              )
            end

            return Result.new(mode: :venues, query:, events: standard_event_loader.call, suggestions: [], venues:)
          end

          Result.new(mode: :events, query:, events: event_loader.call, suggestions: [], venues: [])
        end

        private

        attr_reader :query, :idle_loader, :event_loader, :standard_event_loader

        def build_venue_query(analysis:, venue:)
          resolution_label = analysis.resolution&.label.to_s
          glue = analysis.venue_glue.to_s
          venue_name = venue_name_for_glue(glue:, venue_name: venue.name)

          "#{resolution_label} #{glue} #{venue_name}".squish
        end

        def venue_name_for_glue(glue:, venue_name:)
          case glue
          when "im"
            venue_name.sub(/\Aim\s+/i, "")
          when "in der"
            venue_name.sub(/\Ader\s+/i, "")
          when "in dem"
            venue_name.sub(/\Adem\s+/i, "")
          else
            venue_name
          end
        end
      end
    end
  end
end
