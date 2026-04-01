module Public
  module News
    class ShowPresenter
      attr_reader :blog_post

      def initialize(blog_post, view_context:)
        @blog_post = blog_post
        @view_context = view_context
      end

      def page_title
        "#{meta_title} | Stuttgart Live"
      end

      def meta_title
        [ blog_post.title.to_s.strip.presence, published_on_label, "News" ].compact.join(" | ")
      end

      def meta_description
        summary_text.truncate(160)
      end

      def canonical_url
        view_context.news_url(blog_post.slug)
      end

      def og_image_url
        return unless hero_image?

        view_context.optimized_blog_post_image_url(blog_post, :cover_image)
      end

      def back_path
        view_context.news_index_path
      end

      def header_classes
        classes = [ "event-detail-header", "news-detail-header" ]
        classes << "event-detail-header-with-image" if hero_image?
        classes << "news-detail-header-with-image" if hero_image?
        classes << "news-detail-header-no-image" unless hero_image?
        classes.join(" ")
      end

      def headline
        blog_post.title
      end

      def teaser
        blog_post.teaser.to_s.strip.presence
      end

      def meta_line
        [ published_on_label, author_meta_label ].compact.join(" ")
      end

      def author_label
        blog_post.display_author_name.to_s.strip.presence || "Redaktion"
      end

      def published_on_label
        return unless blog_post.published_at.present?

        view_context.l(blog_post.published_at.to_date, format: "%d.%m.%Y")
      end

      def hero_image?
        blog_post.cover_image.attached?
      end

      def hero_image_source
        return unless hero_image?

        view_context.optimized_blog_post_image_url(blog_post, :cover_image)
      end

      def hero_alt_text
        headline
      end

      def hero_image_credit
        view_context.blog_post_image_copyright(blog_post, :cover_image).presence
      end

      def body
        blog_post.body
      end

      def has_video_block?
        video_urls.any?
      end

      def video_urls
        blog_post.youtube_video_urls
      end

      def schema_json_ld
        {
          "@context" => "https://schema.org",
          "@type" => "NewsArticle",
          headline: headline,
          description: meta_description,
          datePublished: blog_post.published_at&.iso8601,
          dateModified: blog_post.updated_at&.iso8601,
          author: {
            "@type" => "Person",
            name: author_label
          },
          mainEntityOfPage: canonical_url,
          url: canonical_url,
          image: og_image_url.presence && [ og_image_url ]
        }.compact.to_json
      end

      private

      attr_reader :view_context

      def summary_text
        teaser.presence || blog_post.body.to_plain_text.squish.presence || headline.to_s
      end

      def author_meta_label
        "von #{author_label}"
      end
    end
  end
end
