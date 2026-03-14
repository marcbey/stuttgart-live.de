module Merging
  class SyncFromImports
    module DuplicationKey
      module_function

      def for_record(record)
        [
          normalize_artist_name(record.artist_name),
          record.start_at.in_time_zone.iso8601
        ].join("::")
      end

      def normalize_artist_name(value)
        I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]/, "")
      end

      def parse_time_components(value)
        raw = value.to_s.strip
        match = raw.match(/(?<!\d)(\d{1,2})[:.](\d{2})(?!\d)/)

        if match.present?
          hour = match[1].to_i
          minute = match[2].to_i
          return [ hour, minute ] if hour.between?(0, 23) && minute.between?(0, 59)
        end

        [ 20, 0 ]
      end
    end
  end
end
