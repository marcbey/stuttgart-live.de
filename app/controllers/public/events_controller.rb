module Public
  class EventsController < ApplicationController
    allow_unauthenticated_access only: [ :index, :lane, :saved, :saved_lane, :search, :show, :search_overlay, :termine ]
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    PER_PAGE = 12
    HOME_LANE_LIMIT = 15
    HOME_CANDIDATE_LIMIT = 100
    SEARCH_OVERLAY_LIMIT = 6
    SEARCH_OVERLAY_IDLE_LIMIT = 10
    SHOW_EVENT_SERIES_TERMS_LIMIT = 6
    RUSS_LIVE_PROMOTER_ID = "382".freeze
    REQUEST_PROFILE_HEADER = "X-Stuttgart-Live-Profile".freeze

    before_action :set_browse_state, only: [ :index, :lane, :saved, :saved_lane, :search, :show, :search_overlay, :termine ]
    around_action :append_index_profile_headers, only: :index

    def index
      if params[:q].present?
        redirect_to(search_redirect_path, allow_other_host: false)
        return
      end

      if @browse_state.page == 1
        homepage_relation = published_visible_events_relation(
          scope: homepage_events_relation,
          filter: @browse_state.filter,
          event_date: @browse_state.event_date,
          query: nil
        )
        assign_homepage_sections(homepage_relation)
        @promotion_banner_event = Event.promotion_banner_live.find(&:promotion_banner_display_image_present?)
        @promotion_banner_blog_post = BlogPost.promotion_banner_live.first
      end

      respond_to do |format|
        format.html
        format.turbo_stream
      end
    end

    def search
      unless @browse_state.search_query_present?
        redirect_to events_path(event_date: @browse_state.event_date_param)
        return
      end

      relation = search_results_relation
      if should_redirect_search_result?(relation)
        event = relation.limit(1).first
        redirect_to event_path(event.slug, **@browse_state.route_params.except(:q))
        return
      end

      @events = relation.to_a
    end

    def lane
      @lane = resolved_lane
      raise ActiveRecord::RecordNotFound if @lane.blank?

      assign_lane_page(@lane)
    end

    def saved
    end

    def saved_lane
      slugs = normalized_saved_lane_slugs
      if slugs.empty?
        render plain: ""
        return
      end

      @saved_lane_events = homepage_events_relation.where(slug: slugs).reorder(:start_at, :id).to_a
      if @saved_lane_events.empty?
        render plain: ""
        return
      end

      render partial: "public/events/saved_events_lane",
             locals: {
               browse_state: @browse_state,
               events: @saved_lane_events
             }
    end

    def show
      @event = show_events_relation.find_by!(slug: params[:slug])
      @primary_offer = @event.public_ticket_offer
      @event_series_lane = Public::Events::EventSeriesLaneBuilder.new(
        event: @event,
        relation: show_event_series_lane_relation,
        exclude_event: @event,
        limit: SHOW_EVENT_SERIES_TERMS_LIMIT
      ).call
      @related_genre_lane = Public::Events::RelatedGenreLaneBuilder.new(
        event: @event,
        relation: show_related_genre_lane_events_relation
      ).call
    end

    def termine
      @event = show_events_relation.find_by!(slug: params[:slug])
      @event_series_lane = Public::Events::EventSeriesLaneBuilder.new(
        event: @event,
        relation: show_event_series_lane_relation
      ).call

      raise ActiveRecord::RecordNotFound if @event_series_lane.blank?
    end

    def search_overlay
      @overlay = Public::Events::Search::OverlayBuilder.build(
        query: @browse_state.query,
        idle_loader: -> { initial_search_overlay_events },
        event_loader: lambda {
          visible_events_relation(
            scope: searchable_index_events_relation,
            filter: Public::Events::BrowseState::FILTER_ALL,
            event_date: @browse_state.event_date,
            query: @browse_state.query
          ).limit(SEARCH_OVERLAY_LIMIT).to_a
        },
        standard_event_loader: lambda {
          visible_events_relation(
            scope: searchable_index_events_relation,
            filter: Public::Events::BrowseState::FILTER_ALL,
            event_date: @browse_state.event_date,
            query: @browse_state.query,
            structured: false
          ).limit(SEARCH_OVERLAY_LIMIT).to_a
        }
      )

      render partial: "public/events/search_overlay",
             locals: {
               browse_state: @browse_state,
               overlay: @overlay
             }
    end

    def status
      browse_state = Public::Events::BrowseState.new(params)
      @event = Event.find_by!(slug: params[:slug])
      desired_status = params[:status].to_s

      unless Event::STATUSES.include?(desired_status)
        redirect_back fallback_location: helpers.public_events_index_path(browse_state, page: browse_state.page)
        return
      end

      apply_status!(@event, desired_status)
      Editorial::EventChangeLogger.log!(
        event: @event,
        action: "public_status_update",
        user: current_user,
        changed_fields: @event.saved_changes
      )

      respond_to do |format|
        format.turbo_stream do
          streams = []
          card_id = helpers.dom_id(@event, :card)

          if @event.live?
            streams << turbo_stream.replace(
              card_id,
              partial: "public/events/event_card",
              locals: {
                event: @event,
                card_slot: params[:card_slot].presence || :grid_default,
                browse_state: browse_state
              }
            )
          else
            streams << turbo_stream.remove(card_id)
          end

          render turbo_stream: streams
        end
        format.html do
          redirect_back fallback_location: helpers.public_events_index_path(browse_state, page: browse_state.page)
        end
      end
    end

    private

    def set_browse_state
      @browse_state = Public::Events::BrowseState.new(params)
    end

    def visible_events_relation(scope: index_events_relation, filter: Public::Events::BrowseState::FILTER_ALL, event_date: nil, query: nil, structured: true)
      Public::VisibleEventsQuery.new(
        scope: scope,
        filter: filter,
        event_date: event_date,
        query: query,
        structured: structured
      ).call
    end

    def published_visible_events_relation(scope: published_future_events_relation, filter: Public::Events::BrowseState::FILTER_ALL, event_date: nil, query: nil, structured: true)
      Public::VisibleEventsQuery.new(
        scope: scope,
        filter: filter,
        event_date: event_date,
        query: query,
        structured: structured
      ).call
    end

    def index_events_relation
      return published_future_events_relation unless authenticated?

      future_events_relation
    end

    def searchable_index_events_relation
      relation = search_events_relation
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .chronological
      return relation.where(status: "published").where("published_at IS NULL OR published_at <= ?", Time.current) unless authenticated?

      exclude_scheduled_published_events(relation)
    end

    def future_events_relation
      list_events_relation
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .chronological
    end

    def published_future_events_relation
      published_events_relation
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
    end

    def assign_homepage_sections(current_relation)
      scoped_highlights = published_visible_events_relation(
        scope: homepage_events_relation,
        filter: Public::Events::BrowseState::FILTER_SKS,
        event_date: @browse_state.event_date,
        query: nil
      ).reorder(:start_at, :id)
      scoped_all = published_visible_events_relation(
        scope: homepage_events_relation,
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: @browse_state.event_date,
        query: nil
      )
      @home_featured_lane = Public::Events::LaneDirectory.highlights
      @home_all_stuttgart_lane = Public::Events::LaneDirectory.all_stuttgart
      @home_tagestipp_lane = Public::Events::LaneDirectory.tagestipp

      @home_featured_events = Public::Events::SeriesRepresentativeSelector.call(scoped_highlights.limit(HOME_CANDIDATE_LIMIT).to_a)
      @home_featured_effective_series_ids = Public::Events::EffectiveSeriesIdsQuery.call(@home_featured_events)

      if @home_featured_events.empty?
        fallback_relation = current_relation.reorder(:start_at, :id)
        @home_featured_events = Public::Events::SeriesRepresentativeSelector.call(fallback_relation.limit(HOME_CANDIDATE_LIMIT).to_a)
        @home_featured_effective_series_ids = Public::Events::EffectiveSeriesIdsQuery.call(@home_featured_events)
      end

      @home_genre_lanes = homepage_genre_lanes
      @home_highlight_events = Public::Events::SeriesRepresentativeSelector.call(scoped_all.limit(HOME_LANE_LIMIT).to_a)
      @home_highlight_effective_series_ids = Public::Events::EffectiveSeriesIdsQuery.call(@home_highlight_events)
      tagestipp_scope = tagestipp_relation
      @home_tagestipp_events = Public::Events::SeriesRepresentativeSelector.call(tagestipp_scope.to_a).first(HOME_LANE_LIMIT)
      @home_tagestipp_effective_series_ids = Public::Events::EffectiveSeriesIdsQuery.call(@home_tagestipp_events)
    end

    def should_redirect_search_result?(relation)
      return false unless @browse_state.search_query_present?
      return false unless @browse_state.page == 1

      relation.limit(2).count == 1
    end

    def search_results_relation
      visible_events_relation(
        scope: searchable_index_events_relation,
        filter: search_filter,
        event_date: @browse_state.event_date,
        query: @browse_state.query
      )
    end

    def search_redirect_path
      return search_path(**@browse_state.route_params) if @browse_state.search_query_present?

      events_path(event_date: @browse_state.event_date_param)
    end

    def published_events_relation
      detail_events_relation
        .published_live
    end

    def homepage_events_relation
      list_events_relation
        .published_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
    end

    def search_events_relation
      list_events_relation
    end

    def homepage_genre_lanes
      Public::Events::HomepageGenreLanesBuilder.new(relation: homepage_events_relation).call
    end

    def initial_search_overlay_events
      promotion_events = initial_search_overlay_events_for(search_overlay_idle_relation.where(promotion_banner: true))
      highlighted_events = initial_search_overlay_events_for(search_overlay_idle_relation.where(highlighted: true))
      sks_events = initial_search_overlay_events_for(search_overlay_idle_relation.where(promoter_id: Event.sks_promoter_ids))

      deduplicate_priority_events(promotion_events, highlighted_events, sks_events).first(SEARCH_OVERLAY_IDLE_LIMIT)
    end

    def initial_search_overlay_events_for(scope)
      visible_events_relation(
        scope: scope,
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: @browse_state.event_date,
        query: nil
      ).limit(SEARCH_OVERLAY_IDLE_LIMIT).to_a
    end

    def search_overlay_idle_relation
      search_events_relation
        .where(status: "published")
        .where("published_at IS NULL OR published_at <= ?", Time.current)
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .chronological
    end

    def deduplicate_priority_events(*groups)
      groups.flatten.each_with_object({}) do |event, deduplicated_events|
        deduplicated_events[event.id] ||= event
      end.values
    end

    def normalized_saved_lane_slugs
      Array(params[:slugs]).filter_map do |slug|
        normalized_slug = slug.to_s.strip
        normalized_slug if normalized_slug.present?
      end.uniq.first(Public::Events::HomepageGenreLanesBuilder::DEFAULT_LIMIT)
    end

    def search_filter
      return Public::Events::BrowseState::FILTER_ALL if @browse_state.search_query_present?

      @browse_state.filter
    end

    def show_events_relation
      return published_events_relation unless authenticated?

      detail_events_relation
    end

    def show_related_genre_lane_events_relation
      list_events_relation
        .published_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
    end

    def show_event_series_lane_relation
      relation = list_events_relation

      authenticated? ? relation : relation.published_live
    end

    def detail_events_relation
      Event.includes(
        :llm_enrichment,
        :genres,
        :event_offers,
        :import_event_images,
        event_images: [ file_attachment: :blob ],
        venue_record: [ logo_attachment: :blob ],
        event_presenters: { presenter: [ logo_attachment: :blob ] }
      )
    end

    def list_events_relation
      Event.includes(
        :venue_record,
        :event_offers,
        :import_event_images,
        event_images: [ file_attachment: :blob ]
      )
    end

    def tagestipp_relation
      published_visible_events_relation(
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: Time.zone.today,
        query: nil
      )
        .reorder(:start_at, :id)
    end

    def assign_lane_page(lane)
      case lane.key
      when "highlights"
        if explicit_sks_filter?
          relation = published_visible_events_relation(
            scope: homepage_events_relation.where(promoter_id: Event.sks_promoter_ids),
            filter: Public::Events::BrowseState::FILTER_ALL,
            event_date: @browse_state.event_date,
            query: nil
          ).reorder(:start_at, :id)
          @lane_effective_series_ids = effective_public_series_ids_for_relation(relation)
          @lane_events = Public::Events::SeriesRepresentativeSelector.call(relation.to_a)
          return
        end

        scoped_highlights = published_visible_events_relation(
          scope: homepage_events_relation,
          filter: Public::Events::BrowseState::FILTER_SKS,
          event_date: @browse_state.event_date,
          query: nil
        ).reorder(:start_at, :id)
        @lane_effective_series_ids = effective_public_series_ids_for_relation(scoped_highlights)
        @lane_events = Public::Events::SeriesRepresentativeSelector.call(scoped_highlights.to_a)

        return unless @lane_events.empty?

        fallback_relation = published_visible_events_relation(
          scope: homepage_events_relation,
          filter: Public::Events::BrowseState::FILTER_ALL,
          event_date: @browse_state.event_date,
          query: nil
        ).reorder(:start_at, :id)
        @lane_effective_series_ids = effective_public_series_ids_for_relation(fallback_relation)
        @lane_events = Public::Events::SeriesRepresentativeSelector.call(fallback_relation.to_a)
      when "russ_live"
        relation = published_visible_events_relation(
          scope: homepage_events_relation.where(promoter_id: RUSS_LIVE_PROMOTER_ID),
          filter: Public::Events::BrowseState::FILTER_ALL,
          event_date: @browse_state.event_date,
          query: nil
        ).reorder(:start_at, :id)
        @lane_effective_series_ids = effective_public_series_ids_for_relation(relation)
        @lane_events = Public::Events::SeriesRepresentativeSelector.call(relation.to_a)
      when "all_stuttgart"
        relation = published_visible_events_relation(
          scope: homepage_events_relation,
          filter: Public::Events::BrowseState::FILTER_ALL,
          event_date: @browse_state.event_date,
          query: nil
        )
        @lane_effective_series_ids = effective_public_series_ids_for_relation(relation)
        @lane_events = Public::Events::SeriesRepresentativeSelector.call(relation.to_a)
      when "tagestipp"
        relation = tagestipp_relation
        @lane_effective_series_ids = effective_public_series_ids_for_relation(relation)
        @lane_events = Public::Events::SeriesRepresentativeSelector.call(relation.to_a)
      when "genre"
        snapshot = LlmGenreGrouping::Lookup.selected_snapshot
        lane_page = Public::Events::HomepageGenreLanesBuilder.new(
          relation: homepage_events_relation,
          slugs: [ lane.group.slug ],
          snapshot: snapshot,
          limit: nil
        ).call.first
        raise ActiveRecord::RecordNotFound if lane_page.blank?

        @lane_effective_series_ids = lane_page.effective_series_ids
        @lane_events = lane_page.events
      else
        raise ActiveRecord::RecordNotFound
      end
    end

    def resolved_lane
      return Public::Events::LaneDirectory.resolve(params[:lane]) if params[:lane].present?

      Public::Events::LaneDirectory.resolve(params[:lane_slug])
    end

    def apply_status!(event, status)
      before_values = event.attributes.slice("status", "published_at", "published_by_id", "auto_published")

      event.status = status
      event.auto_published = false
      event.sync_publication_fields(user: current_user)
      event.save!
      after_values = event.attributes.slice("status", "published_at", "published_by_id", "auto_published")
      before_values != after_values
    end

    def effective_public_series_ids_for_relation(relation)
      Public::Events::EffectiveSeriesIdsQuery.call(relation)
    end

    def explicit_sks_filter?
      params[:filter].to_s == Public::Events::BrowseState::FILTER_SKS
    end

    def exclude_scheduled_published_events(relation)
      events = Event.arel_table
      publicly_live = events[:status].eq("published").and(events[:published_at].eq(nil).or(events[:published_at].lteq(Time.current)))

      relation.where(events[:status].not_eq("published").or(publicly_live))
    end

    def render_not_found
      respond_to do |format|
        format.html do
          @browse_state ||= Public::Events::BrowseState.new(params)
          render "public/events/not_found", status: :not_found
        end
        format.any { head :not_found }
      end
    end

    def append_index_profile_headers
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      return unless index_profile_requested?

      wall_ms = elapsed_milliseconds_since(started_at)
      profile_payload = {
        wall_ms: wall_ms,
        view_ms: view_runtime.to_f.round(1),
        sql_ms: db_runtime.to_f.round(1),
        queries: ActiveRecord::RuntimeRegistry.stats.queries_count,
        cached_queries: ActiveRecord::RuntimeRegistry.stats.cached_queries_count
      }

      response.set_header(REQUEST_PROFILE_HEADER, profile_payload.map { |key, value| "#{key}=#{value}" }.join(", "))
      response.set_header("Server-Timing", server_timing_header(profile_payload))
    end

    def index_profile_requested?
      params[:profile].present? || request.headers[REQUEST_PROFILE_HEADER].present?
    end

    def elapsed_milliseconds_since(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(1)
    end

    def server_timing_header(profile_payload)
      [
        "app;dur=#{profile_payload[:wall_ms]}",
        "view;dur=#{profile_payload[:view_ms]}",
        "sql;dur=#{profile_payload[:sql_ms]}"
      ].join(", ")
    end
  end
end
