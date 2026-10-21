module Public
  class NewsController < ApplicationController
    allow_unauthenticated_access only: %i[index show]
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    INDEX_PAGE_SIZE = 10
    before_action :set_browse_state

    def index
      assign_blog_posts_page

      respond_to do |format|
        format.html { assign_design_news_chrome }
        format.turbo_stream
      end
    end

    def show
      @blog_post = BlogPost.published_live.with_rich_text_body_and_embeds.with_attached_cover_image.find_by!(slug: params[:slug])
      assign_design_news_chrome
    end

    private
      def set_browse_state
        @browse_state = Public::Events::BrowseState.new(params)
      end

      def assign_blog_posts_page
        @offset = [ params[:offset].to_i, 0 ].max
        records = BlogPost.published_live.with_attached_cover_image.offset(@offset).limit(INDEX_PAGE_SIZE + 1).to_a

        @blog_posts = records.first(INDEX_PAGE_SIZE)
        @has_more_blog_posts = records.size > @blog_posts.size
        @next_offset = @offset + @blog_posts.size
      end

      def assign_design_news_chrome
        assign_news_preview_sidebar_events
        @news_preview_effective_series_ids =
          Public::Events::EffectiveSeriesIdsQuery.call(@news_preview_sidebar_events)
        @news_preview_series_counts_by_id =
          Public::Events::SeriesCountsByIdQuery.call(@news_preview_sidebar_events)
      end

      def news_preview_highlight_events
        selected_events = visible_events_relation(
          scope: news_preview_events_relation.homepage_highlights,
          event_date: @browse_state.event_date,
          query: nil,
          structured: true
        ).limit(24).to_a

        Public::Events::SeriesRepresentativeSelector.call(selected_events).first(7)
      end

      def assign_news_preview_sidebar_events
        @news_preview_sidebar_genre = news_preview_sidebar_genre
        @news_preview_sidebar_events = news_preview_sidebar_events
        @news_preview_sidebar_title = @news_preview_sidebar_genre&.name || "Unsere Highlights"
      end

      def news_preview_sidebar_genre
        return if @blog_post.blank?

        Public::News::RelatedGenreResolver.call(
          blog_post: @blog_post,
          relation: news_preview_events_relation
        )
      end

      def news_preview_sidebar_events
        return news_preview_highlight_events if @news_preview_sidebar_genre.blank?

        selected_events = visible_events_relation(
          scope: news_preview_events_relation.joins(:genres).where(genres: { id: @news_preview_sidebar_genre.id }).distinct,
          event_date: @browse_state.event_date,
          query: nil,
          structured: true
        ).limit(24).to_a

        events = Public::Events::SeriesRepresentativeSelector.call(selected_events).first(7)
        return events if events.any?

        @news_preview_sidebar_genre = nil
        news_preview_highlight_events
      end

      def visible_events_relation(scope:, event_date:, query:, structured:)
        Public::VisibleEventsQuery.new(
          scope: scope,
          filter: Public::Events::BrowseState::FILTER_ALL,
          event_date: event_date,
          query: query,
          structured: structured
        ).call
      end

      def news_preview_events_relation
        Event.preload(
          :genres,
          :venue_record,
          :event_offers,
          { import_event_images: { prepared_file_attachment: { blob: { variant_records: { image_attachment: :blob } } } } },
          event_images: [ file_attachment: { blob: { variant_records: { image_attachment: :blob } } } ]
        )
          .published_live
          .where("start_at >= ?", Time.zone.today.beginning_of_day)
      end

      def render_not_found
        render plain: "Nicht gefunden", status: :not_found
      end
  end
end
