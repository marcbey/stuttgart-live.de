require "open-uri"

module Blog
  class WordpressImporter
    CATEGORY_ID = 1
    POSTS_ENDPOINT = "https://stuttgart-live.de/wp-json/wp/v2/posts".freeze
    PER_PAGE = 100

    Result = Struct.new(:created_count, :updated_count, :errors, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def self.default_author
      User.where(role: "admin").order(:id).first ||
        User.where(role: "editor").order(:id).first ||
        User.order(:id).first ||
        raise("No user available for blog import")
    end

    def initialize(author: self.class.default_author, logger: Rails.logger)
      @author = author
      @logger = logger
      @created_count = 0
      @updated_count = 0
      @errors = []
      @document_cache = {}
    end

    def call
      posts.each do |payload|
        import_post(payload)
      rescue StandardError => error
        errors << { id: payload["id"], title: payload.dig("title", "rendered"), error: error.message }
        logger.error("Wordpress blog import failed for post #{payload["id"]}: #{error.class}: #{error.message}")
      end

      Result.new(created_count: created_count, updated_count: updated_count, errors: errors)
    end

    private
      attr_reader :author, :logger, :created_count, :updated_count, :errors

      def posts
        source_posts.sort_by do |payload|
          [
            parse_time(payload["date_gmt"]) || parse_time(payload["date"]) || Time.zone.at(0),
            payload.fetch("id").to_i
          ]
        end
      end

      def source_posts
        page = 1
        payloads = []

        loop do
          response = URI.parse("#{POSTS_ENDPOINT}?categories=#{CATEGORY_ID}&per_page=#{PER_PAGE}&page=#{page}&_embed=1").open.read
          page_payloads = JSON.parse(response)
          break if page_payloads.empty?

          payloads.concat(page_payloads)
          break if page_payloads.size < PER_PAGE

          page += 1
        end

        payloads
      end

      def import_post(payload)
        blog_post = BlogPost.find_or_initialize_by(source_identifier: payload.fetch("id").to_s)
        blog_post.author = author
        blog_post.author_name = author_name_for(payload)
        blog_post.source_identifier = payload["id"].to_s
        blog_post.source_url = payload["link"]
        blog_post.slug = payload["slug"]
        blog_post.title = plain_text(payload.dig("title", "rendered"))
        blog_post.teaser = teaser_for(payload)
        blog_post.body = payload.dig("content", "rendered").to_s
        blog_post.status = "published"
        blog_post.published_at = parse_time(payload["date_gmt"]) || parse_time(payload["date"])
        blog_post.published_by = author
        blog_post.youtube_video_urls = youtube_video_urls_for(payload)

        new_record = blog_post.new_record?
        blog_post.save!
        import_cover_image(blog_post, payload)

        if new_record
          @created_count += 1
        else
          @updated_count += 1
        end
      end

      def teaser_for(payload)
        teaser = plain_text(payload.dig("excerpt", "rendered"))
        teaser = plain_text(payload.dig("yoast_head_json", "description")) if teaser.blank?
        teaser = plain_text(payload.dig("content", "rendered")).truncate(320) if teaser.blank?
        teaser.to_s.first(320)
      end

      def plain_text(value)
        CGI.unescapeHTML(Nokogiri::HTML.fragment(value.to_s).text).tr("\u00A0", " ").squish
      end

      def author_name_for(payload)
        embedded_author = payload.dig("_embedded", "author", 0, "name").to_s.strip
        return embedded_author if embedded_author.present?

        document_for(payload["link"]).at_css('meta[name="author"]')&.[]("content").to_s.strip.presence ||
          document_for(payload["link"]).at_css(".author.vcard")&.text.to_s.strip.presence
      end

      def youtube_video_urls_for(payload)
        document = document_for(payload["link"])
        urls = []

        document.css("iframe").each do |iframe|
          src = iframe["src"].to_s
          urls << src if src.match?(/youtube|youtu\.be/)
        end

        document.css("[data-borlabs-cookie-content]").each do |node|
          decoded = Base64.decode64(node["data-borlabs-cookie-content"].to_s)
          fragment = Nokogiri::HTML.fragment(decoded)
          fragment.css("iframe").each do |iframe|
            src = iframe["src"].to_s
            urls << src if src.match?(/youtube|youtu\.be/)
          end
        rescue ArgumentError
          next
        end

        urls.uniq
      end

      def parse_time(value)
        return if value.blank?

        Time.zone.parse(value.to_s)
      end

      def import_cover_image(blog_post, payload)
        media = payload.dig("_embedded", "wp:featuredmedia", 0)
        image_url = media&.dig("source_url").presence
        return if image_url.blank?
        return if cover_image_matches?(blog_post, image_url)

        tempfile = URI.parse(image_url).open
        filename = File.basename(URI.parse(image_url).path).presence || "cover-image"

        blog_post.cover_image.attach(
          io: tempfile,
          filename: filename,
          content_type: media["mime_type"].presence || tempfile.content_type
        )
      ensure
        tempfile&.close if tempfile.respond_to?(:close)
      end

      def cover_image_matches?(blog_post, image_url)
        return false unless blog_post.cover_image.attached?

        blog_post.cover_image.blob.filename.to_s == File.basename(URI.parse(image_url).path)
      end
      def document_for(url)
        @document_cache[url] ||= Nokogiri::HTML(URI.parse(url).open.read)
      end
  end
end
