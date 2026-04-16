module Public
  module Events
    module Search
      class TimePhraseResolver
        Resolution = Data.define(:type, :from, :to, :label, :canonical_phrase)

        WEEKDAYS = {
          monday: { name: "Montag", aliases: %w[mo mon montag] },
          tuesday: { name: "Dienstag", aliases: %w[di die dienstag] },
          wednesday: { name: "Mittwoch", aliases: %w[mi mit mittwoch] },
          thursday: { name: "Donnerstag", aliases: %w[do don donnerstag] },
          friday: { name: "Freitag", aliases: %w[fr fre freitag] },
          saturday: { name: "Samstag", aliases: %w[sa sam samstag] },
          sunday: { name: "Sonntag", aliases: %w[so son sonntag] }
        }.freeze

        MONTHS = {
          january: { name: "Januar", aliases: %w[jan januar], number: 1 },
          february: { name: "Februar", aliases: %w[feb februar], number: 2 },
          march: { name: "März", aliases: %w[mar maerz maerz], number: 3 },
          april: { name: "April", aliases: %w[apr april], number: 4 },
          may: { name: "Mai", aliases: %w[mai], number: 5 },
          june: { name: "Juni", aliases: %w[jun juni], number: 6 },
          july: { name: "Juli", aliases: %w[jul juli], number: 7 },
          august: { name: "August", aliases: %w[aug august], number: 8 },
          september: { name: "September", aliases: %w[sep sept september], number: 9 },
          october: { name: "Oktober", aliases: %w[okt oktober], number: 10 },
          november: { name: "November", aliases: %w[nov november], number: 11 },
          december: { name: "Dezember", aliases: %w[dez dezember], number: 12 }
        }.freeze

        STATIC_PHRASES = {
          "heute" => { type: :today, label: "Heute" },
          "morgen" => { type: :tomorrow, label: "Morgen" },
          "uebermorgen" => { type: :day_after_tomorrow, label: "Übermorgen" },
          "am wochenende" => { type: :coming_weekend, label: "Am Wochenende" },
          "diese woche" => { type: :this_week, label: "Diese Woche" },
          "dieses wochenende" => { type: :this_weekend, label: "Dieses Wochenende" },
          "naechstes wochenende" => { type: :next_weekend, label: "Nächstes Wochenende" },
          "uebernaechstes wochenende" => { type: :week_after_next_weekend, label: "Übernächstes Wochenende" },
          "naechste woche" => { type: :next_week, label: "Nächste Woche" }
        }.freeze

        DATE_PATTERN = /\A(\d{1,2})\.(\d{1,2})\.(\d{4})?\z/.freeze

        def self.resolve(type:, value: nil, now: Time.zone.now)
          new(type:, value:, now:).call
        end

        def self.weekday_aliases
          @weekday_aliases ||= WEEKDAYS.each_with_object({}) do |(key, config), mapping|
            config.fetch(:aliases).each { |alias_name| mapping[alias_name] = key }
          end
        end

        def self.month_aliases
          @month_aliases ||= MONTHS.each_with_object({}) do |(key, config), mapping|
            config.fetch(:aliases).each { |alias_name| mapping[alias_name] = key }
          end
        end

        def self.full_weekday_names
          WEEKDAYS.transform_values { |config| config.fetch(:name) }
        end

        def self.full_month_names
          MONTHS.transform_values { |config| config.fetch(:name) }
        end

        def initialize(type:, value:, now:)
          @type = type
          @value = value
          @now = now.in_time_zone
        end

        def call
          case type
          when :today
            day_resolution(date: today, label: "Heute", canonical_phrase: "heute")
          when :tomorrow
            day_resolution(date: today + 1.day, label: "Morgen", canonical_phrase: "morgen")
          when :day_after_tomorrow
            day_resolution(date: today + 2.days, label: "Übermorgen", canonical_phrase: "uebermorgen")
          when :coming_weekend
            weekend_resolution(range: coming_weekend_range, label: "Am Wochenende", canonical_phrase: "am wochenende")
          when :this_weekend
            weekend_resolution(range: this_weekend_range, label: "Dieses Wochenende", canonical_phrase: "dieses wochenende")
          when :next_weekend
            weekend_resolution(range: next_weekend_range, label: "Nächstes Wochenende", canonical_phrase: "naechstes wochenende")
          when :week_after_next_weekend
            weekend_resolution(
              range: week_after_next_weekend_range,
              label: "Übernächstes Wochenende",
              canonical_phrase: "uebernaechstes wochenende"
            )
          when :this_week
            week_resolution(range: this_week_range, label: "Diese Woche", canonical_phrase: "diese woche")
          when :next_week
            week_resolution(range: next_week_range, label: "Nächste Woche", canonical_phrase: "naechste woche")
          when :this_month
            this_month_resolution
          when :next_month
            next_month_resolution
          when :this_weekday
            weekday_resolution(reference_date: beginning_of_week + weekday_offset(value), label_prefix: "Diesen", canonical_prefix: "diesen")
          when :next_weekday
            weekday_resolution(reference_date: beginning_of_week + 1.week + weekday_offset(value), label_prefix: "Nächsten", canonical_prefix: "naechsten")
          when :month
            month_resolution(month_key: value)
          when :date
            explicit_date_resolution(raw_date: value)
          else
            raise ArgumentError, "Unsupported time phrase type: #{type.inspect}"
          end
        end

        private

        attr_reader :type, :value, :now

        def today
          now.to_date
        end

        def beginning_of_week
          today.beginning_of_week(:monday)
        end

        def coming_weekend_range
          return weekend_range_for(today.beginning_of_week(:monday)) if today.saturday? || today.sunday?

          weekend_range_for(beginning_of_week)
        end

        def this_weekend_range
          weekend_range_for(beginning_of_week)
        end

        def next_weekend_range
          weekend_range_for(beginning_of_week + 1.week)
        end

        def week_after_next_weekend_range
          weekend_range_for(beginning_of_week + 2.weeks)
        end

        def this_week_range
          beginning_of_week..(beginning_of_week + 6.days)
        end

        def next_week_range
          week_start = beginning_of_week + 1.week
          week_start..(week_start + 6.days)
        end

        def this_month_range
          first_day = today.beginning_of_month
          first_day..first_day.end_of_month
        end

        def next_month_range
          first_day = today.next_month.beginning_of_month
          first_day..first_day.end_of_month
        end

        def weekend_range_for(week_start)
          friday = week_start + 4.days
          friday..(friday + 2.days)
        end

        def weekday_offset(weekday_key)
          {
            monday: 0,
            tuesday: 1,
            wednesday: 2,
            thursday: 3,
            friday: 4,
            saturday: 5,
            sunday: 6
          }.fetch(weekday_key)
        end

        def weekday_resolution(reference_date:, label_prefix:, canonical_prefix:)
          name = self.class.full_weekday_names.fetch(value)
          Resolution.new(
            type:,
            from: reference_date.beginning_of_day,
            to: reference_date.end_of_day,
            label: "#{label_prefix} #{name}",
            canonical_phrase: "#{canonical_prefix} #{Normalizer.normalize_parser(name)}"
          )
        end

        def month_resolution(month_key:)
          config = self.class::MONTHS.fetch(month_key)
          year = config.fetch(:number) >= today.month ? today.year : today.year + 1
          first_day = Date.new(year, config.fetch(:number), 1)
          last_day = first_day.end_of_month

          Resolution.new(
            type:,
            from: first_day.beginning_of_day.in_time_zone,
            to: last_day.end_of_day.in_time_zone,
            label: "Im #{config.fetch(:name)}",
            canonical_phrase: "im #{Normalizer.normalize_parser(config.fetch(:name))}"
          )
        end

        def explicit_date_resolution(raw_date:)
          match = DATE_PATTERN.match(raw_date.to_s)
          raise ArgumentError, "Unsupported date format: #{raw_date.inspect}" unless match

          day = match[1].to_i
          month = match[2].to_i
          year = if match[3].present?
            match[3].to_i
          else
            current_year_candidate = Date.new(today.year, month, day)
            current_year_candidate >= today ? today.year : today.year + 1
          end

          date = Date.new(year, month, day)
          Resolution.new(
            type:,
            from: date.beginning_of_day.in_time_zone,
            to: date.end_of_day.in_time_zone,
            label: "Am #{display_date(raw_date)}",
            canonical_phrase: "am #{Normalizer.normalize_parser(raw_date)}"
          )
        end

        def day_resolution(date:, label:, canonical_phrase:)
          Resolution.new(
            type:,
            from: date.beginning_of_day.in_time_zone,
            to: date.end_of_day.in_time_zone,
            label:,
            canonical_phrase:
          )
        end

        def weekend_resolution(range:, label:, canonical_phrase:)
          Resolution.new(
            type:,
            from: range.begin.beginning_of_day.in_time_zone,
            to: range.end.end_of_day.in_time_zone,
            label:,
            canonical_phrase:
          )
        end

        def week_resolution(range:, label:, canonical_phrase:)
          Resolution.new(
            type:,
            from: range.begin.beginning_of_day.in_time_zone,
            to: range.end.end_of_day.in_time_zone,
            label:,
            canonical_phrase:
          )
        end

        def next_month_resolution
          range = next_month_range

          Resolution.new(
            type:,
            from: range.begin.beginning_of_day.in_time_zone,
            to: range.end.end_of_day.in_time_zone,
            label: "Nächsten Monat",
            canonical_phrase: "naechsten monat"
          )
        end

        def this_month_resolution
          range = this_month_range

          Resolution.new(
            type:,
            from: range.begin.beginning_of_day.in_time_zone,
            to: range.end.end_of_day.in_time_zone,
            label: "Diesen Monat",
            canonical_phrase: "diesen monat"
          )
        end

        def display_date(raw_date)
          raw_date.to_s.sub(/\A0+(\d)/, '\1')
        end
      end
    end
  end
end
