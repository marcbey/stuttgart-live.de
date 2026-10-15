require "digest"

module LegacyRedirects
  class Inventory
    DEFAULT_SOURCE = "https://stuttgart-live.de"
    EXTRACTED_KEYS = %w[title content artist_name production venue date start_at time_known dates provider_ids published_at wordpress_id checksum content_type crawl_error crawled_at discovered_links discovered_media].freeze

    def initialize(fetcher: HttpFetcher.new, source_url: DEFAULT_SOURCE, refresh: false, max_pages: 10_000, max_sitemaps: 1_000)
      @base = URI.parse(source_url)
      unless SourceKey::HOSTS.include?(@base.host) && %w[http https].include?(@base.scheme) && @base.userinfo.nil? && @base.port == @base.default_port && @base.path.in?([ "", "/" ]) && @base.query.nil? && @base.fragment.nil?
        raise ArgumentError, "Source must be the root of an allowed legacy host"
      end
      @base = "#{@base.scheme}://#{@base.host}"
      @fetcher, @refresh = fetcher, refresh
      @max_pages, @max_sitemaps = Integer(max_pages), Integer(max_sitemaps)
      raise ArgumentError, "Limits must be positive" unless @max_pages.positive? && @max_sitemaps.positive?
      @counts = Hash.new(0)
      @queued = Set.new
      @queue = []
    end

    def call
      load_robots
      discover_sitemaps
      LegacyRedirect.where("source_metadata ->> 'crawled_at' IS NULL OR source_metadata ? 'crawl_error'").find_each do |row|
        enqueue("#{@base}#{row.source_path}", kind: row.source_kind)
      end
      until @queue.empty? || @counts[:fetched] >= @max_pages
        path = @queue.shift
        crawl(LegacyRedirect.find_by!(source_path: path))
      end
      @counts.merge(pending: @queue.size, limit: @max_pages)
    end

    def seed_blog_posts
      sources = Hash.new { |hash, key| hash[key] = [] }
      BlogPost.published_live.where.not(source_url: [ nil, "" ]).find_each do |post|
        path = SourceKey.normalize(post.source_url)
        sources[path] << post if path
      end
      sources.each do |path, posts|
        next unless posts.one?
        post = posts.first
        row = find_source(path, "news")
        row.with_lock do
          next if row.manual? || row.disabled?
          probe = LegacyRedirect.new(source_path: path, source_kind: "news", target: post)
          destination = Target.path_for(probe)
          next unless destination && destination != path
          row.update!(source_kind: "news", target: post, target_path: nil, status: "redirect", match_reason: "blog_source_url", score: 1.0, checked_at: Time.current)
        end
      end
    end

    private

    def load_robots
      body = @fetcher.call("#{@base}/robots.txt").body
      groups, agents, rules, directives_seen = [], [], [], false
      body.each_line do |line|
        key, value = line.sub(/#.*/, "").strip.split(":", 2).map(&:strip)
        next if key.blank? || value.nil?
        if key.casecmp?("user-agent")
          if directives_seen
            groups << [ agents, rules ]
            agents, rules, directives_seen = [], [], false
          end
          agents << value.downcase
        elsif agents.any?
          directives_seen = true
          rules << [ key.downcase, value ] if key.downcase.in?(%w[disallow allow]) && value.present?
        end
      end
      groups << [ agents, rules ]
      specific = groups.select { |names, _| names.any? { |name| name != "*" && "stuttgartliveredirectinventory".include?(name) } }
      @robots = (specific.presence || groups.select { |names, _| names.include?("*") }).flat_map(&:last)
    rescue HttpFetcher::Error => error
      raise unless error.message == "HTTP 404"
      @robots = []
    end

    def allowed?(url)
      path = SourceKey.normalize(url)
      return unless path
      return if path.match?(%r{\A/(?:wp-admin|wp-json|wp-login\.php)(?:/|\z)|/(?:feed|comments/feed)(?:/|\z)|/page/\d+(?:/|\z)}i)
      robots_path = path
      robots_path += "/" if path != "/" && url.to_s.split(/[?#]/, 2).first.end_with?("/")
      matches = @robots.select do |_, pattern|
        anchored = pattern.end_with?("$")
        regexp = Regexp.escape(pattern.delete_suffix("$")).gsub('\\*', ".*")
        robots_path.match?(Regexp.new("\\A#{regexp}#{anchored ? '\\z' : ''}"))
      end
      winner = matches.max_by { |action, pattern| [ pattern.delete("*$").length, action == "allow" ? 1 : 0 ] }
      path unless winner&.first == "disallow"
    end

    def discover_sitemaps
      queue, seen = [ "#{@base}/sitemap_index.xml" ], Set.new
      until queue.empty? || seen.size >= @max_sitemaps
        url = queue.shift
        next if seen.include?(url) || !allowed?(url)
        seen << url
        document = Nokogiri::XML(@fetcher.call(url, allowed: method(:allowed?)).body) { |config| config.strict.nonet }
        namespaces = { "sm" => "http://www.sitemaps.org/schemas/sitemap/0.9", "image" => "http://www.google.com/schemas/sitemap-image/1.1" }
        document.xpath("/sm:sitemapindex/sm:sitemap/sm:loc", namespaces).each do |node|
          next unless allowed?(node.text)
          queue << node.text unless queue.size >= @max_sitemaps
        end
        document.xpath("/sm:urlset/sm:url/sm:loc", namespaces).each do |node|
          enqueue(node.text, kind: sitemap_kind(url))
        end
        document.xpath("/sm:urlset/sm:url/image:image/image:loc", namespaces).each { |node| enqueue(node.text, kind: "file") }
      end
      @counts[:sitemaps] = seen.size
      @counts[:sitemap_limit_reached] = queue.any?
    end

    def sitemap_kind(url)
      case url
      when /(?:stgtlv_events|event)[-_]sitemap/ then "event"
      when /post[-_]sitemap/ then "news"
      when /genre[-_]sitemap/ then "genre"
      else "page"
      end
    end

    def enqueue(url, kind: nil)
      path = allowed?(url)
      return unless path
      return if @queued.include?(path) || @queued.size >= 100_000
      @queued << path
      kind = "file" if path.match?(PageExtractor::MEDIA_PATTERN)
      kind ||= path.start_with?("/events/", "/stgtlv_events/") ? "event" : "page"
      row = find_source(path, kind)
      if kind != "page" && row.source_kind != kind
        row.with_lock do
          row.update_columns(source_kind: kind, checked_at: nil, updated_at: Time.current) unless row.manual? || row.disabled?
        end
      end
      @queue << path
      row
    end

    def find_source(path, kind)
      row = LegacyRedirect.find_by(source_path: path)
      return row if row
      LegacyRedirect.insert_all([ { source_path: path, source_kind: kind } ], unique_by: :index_legacy_redirects_on_source_path)
      LegacyRedirect.find_by!(source_path: path)
    end

    def crawl(row)
      if !@refresh && row.source_metadata["crawled_at"].present? && row.source_metadata["crawl_error"].blank?
        discover_saved_links(row)
        @counts[:resumed] += 1
        return
      end
      url = "#{@base}#{row.source_path}"
      @counts[:fetched] += 1
      response = @fetcher.call(url, max_bytes: row.source_kind == "file" ? HttpFetcher::MEDIA_LIMIT : HttpFetcher::HTML_LIMIT, allowed: method(:allowed?))
      metadata = { "content_type" => response.content_type, "source_url" => url, "crawled_at" => Time.current.iso8601 }
      if row.source_kind == "file"
        metadata["checksum"] = Digest::MD5.base64digest(response.body)
      else
        raise HttpFetcher::Error, "Unexpected content type: #{response.content_type}" unless response.content_type.in?(%w[text/html application/xhtml+xml])
        result = PageExtractor.new(response.body, url: response.url).call
        metadata.merge!(result.metadata)
        metadata["discovered_links"] = result.links.filter_map { |link| allowed?(link) }.uniq
        metadata["discovered_media"] = result.media.filter_map { |link| allowed?(link) }.uniq
      end
      save_metadata(row, metadata)
      discover_saved_links(row)
      @counts[:succeeded] += 1
    rescue HttpFetcher::Error => error
      row.with_lock do
        row.update_columns(source_metadata: row.source_metadata.except("crawled_at").merge("crawl_error" => error.message, "source_url" => url), updated_at: Time.current)
      end
      @counts[:errors] += 1
    end

    def save_metadata(row, metadata)
      row.with_lock do
        existing = row.source_metadata
        replacement = existing.except(*EXTRACTED_KEYS).merge(metadata)
        meaningful = ->(value) { value.except("crawled_at", "crawl_error", "discovered_links", "discovered_media") }
        changed = meaningful.call(existing) != meaningful.call(replacement)
        attributes = { source_metadata: replacement, updated_at: Time.current }
        attributes[:checked_at] = nil if changed && !row.manual? && !row.disabled?
        # Source evidence remains writable when its existing target is no longer public.
        row.update_columns(attributes)
      end
    end

    def discover_saved_links(row)
      Array(row.source_metadata["discovered_links"]).each { |path| enqueue("#{@base}#{path}") }
      Array(row.source_metadata["discovered_media"]).each { |path| enqueue("#{@base}#{path}", kind: "file") }
    end
  end
end
