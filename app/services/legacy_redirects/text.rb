module LegacyRedirects
  module Text
    STOP_WORDS = %w[und and the der die das ein eine mit von fuer im in am an zum zur tickets live band].freeze
    module_function

    def normalize(value)
      plain = Nokogiri::HTML.fragment(value.to_s).text
      I18n.transliterate(plain).downcase.gsub(/[^a-z0-9]+/, " ").split.reject { |word| STOP_WORDS.include?(word) }.join(" ")
    end

    def similarity(left, right)
      left = normalize(left)
      right = normalize(right)
      return 0.0 if left.blank? || right.blank?
      return 1.0 if left == right

      connection = ApplicationRecord.connection
      connection.select_value("SELECT similarity(#{connection.quote(left)}, #{connection.quote(right)})").to_f
    end

    def compatible_years?(left, right)
      left_years = left.to_s.scan(/\b(?:19|20)\d{2}\b/).uniq
      right_years = right.to_s.scan(/\b(?:19|20)\d{2}\b/).uniq
      left_years.empty? || right_years.empty? || left_years.sort == right_years.sort
    end

    def compatible_content?(left, right)
      left_words = normalize(left).split.select { |word| word.length >= 4 }.uniq
      right_words = normalize(right).split.select { |word| word.length >= 4 }.uniq
      return false if left_words.empty? || right_words.empty?

      overlap = (left_words & right_words).size
      overlap >= [ 3, left_words.size, right_words.size ].min &&
        overlap.to_f / [ left_words.size, right_words.size ].min >= 0.5
    end

    def compatible_numbers?(left, right)
      left_numbers = left.to_s.scan(/\d+/).map(&:to_i).uniq.sort
      right_numbers = right.to_s.scan(/\d+/).map(&:to_i).uniq.sort
      left_numbers.empty? || right_numbers.empty? || left_numbers == right_numbers
    end

    def compatible_editions?(left, right)
      left_ids = edition_ids(left)
      right_ids = edition_ids(right)
      (left_ids.keys & right_ids.keys).all? { |key| left_ids[key].sort == right_ids[key].sort }
    end

    def edition_ids(value)
      plain = Nokogiri::HTML.fragment(value.to_s).text.downcase
      labels = "ausgabe|edition|auflage|jahrgang|folge|teil|volume|vol\\.?|nummer|nr\\.?"
      pairs = plain.scan(/\b(#{labels})\s*(?:nr\.?\s*)?(\d+|[ivxlcdm]+)\b/i)
      pairs.concat(plain.scan(/\b(\d+)\.\s*(#{labels})\b/i).map(&:reverse))
      pairs.each_with_object({}) do |(label, number), result|
        next if !number.match?(/\A\d+\z/) && !number.upcase.match?(/\A(?=[MDCLXVI]+\z)M{0,4}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})\z/)

        label = case label.delete(".")
        when "ausgabe", "edition", "auflage", "jahrgang" then "edition"
        when "folge", "teil", "volume", "vol" then "part"
        else "number"
        end
        identifier = number.match?(/\A\d+\z/) ? number.to_i.to_s : number.upcase
        (result[label] ||= []) << identifier unless result[label]&.include?(identifier)
      end
    end
  end
end
