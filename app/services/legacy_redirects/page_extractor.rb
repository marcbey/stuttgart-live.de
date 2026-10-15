module LegacyRedirects
  class PageExtractor
    Result = Data.define(:metadata, :links, :media)
    MONTHS = %w[januar februar märz april mai juni juli august september oktober november dezember].each_with_index.to_h { |name, index| [ name, index + 1 ] }.freeze
    TIME_SUFFIX = /(?:[\s,|–—-]+(?:um\s+)?(\d{1,2})[:.](\d{2})\s*(?:Uhr)?)?/
    DATE_PATTERN = /(\d{1,2})\.\s*(Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember)\s+(\d{4})#{TIME_SUFFIX}/i
    NUMERIC_DATE_PATTERN = /\b(\d{1,2})\.(\d{1,2})\.(\d{4})#{TIME_SUFFIX}/
    MEDIA_PATTERN = /\.(?:jpe?g|png|gif|webp|svg|pdf|avif)(?:\z|\?)/i

    def initialize(html, url:)
      @document = Nokogiri::HTML(html)
      @url = url
    end

    def call
      main = (@document.at_css("article") || @document.at_css("main, #main, #content, body") || @document).dup
      main.css("script, style, nav, footer, aside, .related, .related-posts, .related-events, .shariff").remove
      title = text(main.at_css("h1")) || webpage["name"]
      dates = extract_dates(main)
      metadata = {
        "title" => title, "content" => text(main.at_css(".entry-content, .post-content") || main) || webpage["description"],
        "artist_name" => title, "production" => production(main),
        "venue" => text(main.at_css('a[href*="/veranstaltungsorte/"], a[href*="/locations/"]')),
        "dates" => dates, "provider_ids" => provider_ids(main),
        "wordpress_id" => wordpress_id, "published_at" => published_at
      }.compact_blank
      metadata.merge!(dates.first) if dates.any?
      links = main.css("a[href]").filter_map { |link| absolute_url(link["href"]) }.uniq
      media = main.css("img[src], source[src], a[href]").filter_map { |node| absolute_url(node["src"] || node["href"]) }.select { |url| url.match?(MEDIA_PATTERN) }
      main.css("[srcset]").each { |node| media.concat(node["srcset"].split(",").filter_map { |item| absolute_url(item.strip.split(/\s+/).first) }) }
      Result.new(metadata: metadata, links: links.reject { |url| url.match?(MEDIA_PATTERN) }, media: media.uniq)
    end

    private

    def text(node)
      node&.text.to_s.gsub(/\s+/, " ").strip.presence
    end

    def production(main)
      explicit = main.at_css(".subtitle, .sub-title, .event-subtitle, .entry-subtitle, .entry-header > p > strong")
      return text(explicit) if explicit
      preceding = main.at_css("h1")&.previous_element
      text(preceding) if preceding&.name == "p" && preceding.at_css("strong")
    end

    def extract_dates(main)
      nodes = main.css("h2, time, [class*='date'], a[title^='Ticket:']")
      evidence = nodes.map { |node| [ node.text, node["title"] ].compact.join(" ") }.join("\n")
      dates = evidence.scan(DATE_PATTERN).filter_map do |day, month, year, hour, minute|
        date_reference(day, MONTHS.fetch(month.downcase), year, hour, minute)
      end
      dates.concat(evidence.scan(NUMERIC_DATE_PATTERN).filter_map { |day, month, year, hour, minute| date_reference(day, month, year, hour, minute) })
      main.css("time[datetime]").each do |node|
        value = node["datetime"]
        next unless value.match?(/\A\d{4}-\d{2}-\d{2}(?:T|\z)/)
        date = Date.iso8601(value.first(10))
        reference = { "date" => date.iso8601, "time_known" => value.include?("T") }
        reference["start_at"] = Time.iso8601(value).iso8601 if reference["time_known"]
        dates << reference
      rescue ArgumentError
        next
      end
      if dates.map { |date| date["date"] }.uniq.one?
        time = text(main.at_css(".event-single-time"))&.match(/Beginn:\s*(\d{1,2}):(\d{2})/i)
        if time
          date = Date.iso8601(dates.first["date"])
          dates << date_reference(date.day, date.month, date.year, time[1], time[2])
        end
      end
      dates.compact.uniq { |date| [ date["date"], date["start_at"] ] }.reject { |date| !date["time_known"] && dates.any? { |other| other && other["date"] == date["date"] && other["time_known"] } }
    end

    def date_reference(day, month, year, hour, minute)
      date = Date.new(year.to_i, month.to_i, day.to_i)
      value = { "date" => date.iso8601, "time_known" => hour.present? }
      if hour.present?
        return unless hour.to_i.between?(0, 23) && minute.to_i.between?(0, 59)
        value["start_at"] = ActiveSupport::TimeZone["Europe/Berlin"].local(date.year, date.month, date.day, hour.to_i, minute.to_i).iso8601
      end
      value
    rescue Date::Error
      nil
    end

    def provider_ids(main)
      main.css('a[href][title^="Ticket:"], .tickets a[href], .ticket a[href], a.ticket[href]').filter_map do |link|
        uri = URI.parse(link["href"].strip)
        if uri.host.to_s.match?(/\A(?:[a-z0-9-]+\.)*easyticket\.de\z/i)
          id = uri.path[%r{/(?:event|veranstaltung)/(\d+)(?:/|\z)}, 1]
          { "source" => "easyticket", "id" => id } if id
        elsif uri.host.to_s.match?(/\A(?:[a-z0-9-]+\.)*eventim\.de\z/i)
          id = uri.path[/(\d+)(?:\/)?\z/, 1]
          { "source" => "eventim", "id" => id } if id
        end
      rescue URI::InvalidURIError
        nil
      end.uniq
    end

    def wordpress_id
      @document.at_css("body")&.[]("class").to_s[/\bpostid-(\d+)\b/, 1] || @document.at_css('link[rel="shortlink"]')&.[]("href").to_s[/[?&]p=(\d+)/, 1]
    end

    def published_at
      @document.at_css('meta[property="article:published_time"]')&.[]("content").presence || json_nodes.filter_map { |node| node["datePublished"] }.first
    end

    def webpage
      json_nodes.find { |node| Array(node["@type"]).include?("WebPage") } || {}
    end

    def json_nodes
      @json_nodes ||= @document.css('script[type="application/ld+json"]').flat_map do |script|
        data = JSON.parse(script.text)
        data.is_a?(Hash) ? [ data, *Array(data["@graph"]) ] : Array(data)
      rescue JSON::ParserError
        []
      end.select { |node| node.is_a?(Hash) }
    end

    def absolute_url(value)
      uri = URI.join(@url, value.to_s.strip)
      uri.fragment = nil
      uri.to_s if %w[http https].include?(uri.scheme)
    rescue URI::InvalidURIError
      nil
    end
  end
end
