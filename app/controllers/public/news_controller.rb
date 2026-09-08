module Public
  class NewsController < ApplicationController
    SEARCH_OVERLAY_LIMIT = 6
    SEARCH_OVERLAY_IDLE_LIMIT = 10

    allow_unauthenticated_access only: %i[index show]
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    INDEX_PAGE_SIZE = 10
    before_action :set_browse_state

    def index
      assign_blog_posts_page
      assign_design_news_chrome

      respond_to do |format|
        format.html
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
        @design_preview_search_overlay = build_search_overlay
        @news_preview_genre_lanes = news_preview_genre_lanes
        @news_preview_highlight_events = news_preview_highlight_events
        assign_news_preview_sidebar_events
        @news_preview_effective_series_ids =
          Public::Events::EffectiveSeriesIdsQuery.call(@news_preview_sidebar_events)
      end

      def build_search_overlay
        Public::Events::Search::OverlayBuilder.build(
          query: @browse_state.query,
          idle_loader: -> { initial_search_overlay_events },
          event_loader: -> { search_overlay_events(structured: true) },
          standard_event_loader: -> { search_overlay_events(structured: false) },
          genre_loader: -> { Public::Events::Search::GenreSuggester.call(@browse_state.query) }
        )
      end

      def search_overlay_events(structured:)
        visible_events_relation(
          scope: news_preview_search_relation,
          event_date: @browse_state.event_date,
          query: @browse_state.query,
          structured: structured
        ).limit(SEARCH_OVERLAY_LIMIT).to_a
      end

      def initial_search_overlay_events
        promotion_events = initial_search_overlay_events_for(news_preview_events_relation.where(promotion_banner: true))
        highlighted_events = initial_search_overlay_events_for(news_preview_events_relation.where(highlighted: true))
        sks_events = initial_search_overlay_events_for(news_preview_events_relation.merge(Event.sks_promoters))

        (promotion_events + highlighted_events + sks_events).uniq(&:id).first(SEARCH_OVERLAY_IDLE_LIMIT)
      end

      def initial_search_overlay_events_for(scope)
        visible_events_relation(
          scope: scope,
          event_date: @browse_state.event_date,
          query: nil,
          structured: true
        ).limit(SEARCH_OVERLAY_IDLE_LIMIT).to_a
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
        return @news_preview_highlight_events if @news_preview_sidebar_genre.blank?

        selected_events = visible_events_relation(
          scope: news_preview_events_relation.joins(:genres).where(genres: { id: @news_preview_sidebar_genre.id }).distinct,
          event_date: @browse_state.event_date,
          query: nil,
          structured: true
        ).limit(24).to_a

        events = Public::Events::SeriesRepresentativeSelector.call(selected_events).first(7)
        return events if events.any?

        @news_preview_sidebar_genre = nil
        @news_preview_highlight_events
      end

      def news_preview_genre_lanes
        Public::Events::HomepageGenreLanesBuilder.new(
          relation: news_preview_events_relation,
          limit: Public::Events::HomepageGenreLanesBuilder::DEFAULT_LIMIT
        ).call.first(5)
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

      def news_preview_search_relation
        news_preview_events_relation.search_priority_first
      end

      def news_preview_events_relation
        Event.includes(
          :venue_record,
          :event_offers,
          :import_event_images,
          event_images: [ file_attachment: :blob ]
        )
          .published_live
          .where("start_at >= ?", Time.zone.today.beginning_of_day)
      end

      def render_not_found
        render plain: "Nicht gefunden", status: :not_found
      end
  end
end
