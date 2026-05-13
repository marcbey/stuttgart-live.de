module Public
  module Seo
    class SitemapBuilder
      Entry = Data.define(:loc, :lastmod, :changefreq, :priority)

      def initialize(view_context:)
        @view_context = view_context
      end

      def call
        [
          root_entry,
          fixed_lane_entries,
          genre_lane_entries,
          static_page_entries,
          news_entries,
          event_entries
        ].flatten
      end

      private

      attr_reader :view_context

      def root_entry
        Entry.new(view_context.root_url, latest_public_update, "hourly", "1.0")
      end

      def fixed_lane_entries
        [
          lane_entry(Public::Events::LaneDirectory.highlights),
          lane_entry(Public::Events::LaneDirectory.all_stuttgart),
          lane_entry(Public::Events::LaneDirectory.tagestipp)
        ].compact
      end

      def genre_lane_entries
        routeable_genres.map do |genre|
          Entry.new(
            "#{view_context.root_url.delete_suffix("/")}/#{genre.slug}",
            genre.updated_at,
            "daily",
            "0.7"
          )
        end
      end

      def static_page_entries
        StaticPage.order(:slug).map do |page|
          Entry.new(view_context.static_page_url(page.slug), page.updated_at, "monthly", "0.5")
        end
      end

      def news_entries
        BlogPost.published_live.map do |post|
          Entry.new(view_context.news_url(post.slug), post.updated_at, "weekly", "0.6")
        end
      end

      def event_entries
        future_live_events.map do |event|
          Entry.new(view_context.event_url(event.slug), event.updated_at, "daily", "0.8")
        end
      end

      def lane_entry(lane)
        return if lane.blank?

        Entry.new(
          "#{view_context.root_url.delete_suffix("/")}#{lane.public_path}",
          latest_public_update,
          "daily",
          lane.featured ? "0.9" : "0.8"
        )
      end

      def routeable_genres
        Genre
          .joins(:events)
          .merge(future_live_events.reorder(nil))
          .distinct
          .order(:slug)
          .select { |genre| Public::Events::LaneDirectory.routeable_genre_slug?(genre.slug) }
      end

      def future_live_events
        Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day)
      end

      def latest_public_update
        [
          future_live_events.maximum(:updated_at),
          BlogPost.published_live.maximum(:updated_at),
          StaticPage.maximum(:updated_at)
        ].compact.max
      end
    end
  end
end
