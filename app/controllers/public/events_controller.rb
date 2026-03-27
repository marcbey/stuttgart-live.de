module Public
  class EventsController < ApplicationController
    allow_unauthenticated_access only: [ :index, :show, :search_overlay ]
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    PER_PAGE = 12
    HOME_HIGHLIGHT_LIMIT = 100
    SEARCH_OVERLAY_LIMIT = 6
    SEARCH_OVERLAY_IDLE_LIMIT = 10

    before_action :set_browse_state, only: [ :index, :show, :search_overlay ]

    def index
      if @browse_state.search_query_present?
        relation = visible_events_relation(
          scope: searchable_index_events_relation,
          filter: search_filter,
          event_date: @browse_state.event_date,
          query: @browse_state.query
        )
        if should_redirect_search_result?(relation)
          event = relation.limit(1).first
          redirect_to event_path(event.slug, **@browse_state.route_params.except(:q))
          return
        end

        @events = relation.to_a
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

    def show
      @event = show_events_relation.find_by!(slug: params[:slug])
      @primary_offer = @event.preferred_ticket_offer
      @event_series_lane = Public::Events::EventSeriesLaneBuilder.new(
        event: @event,
        relation: show_event_series_lane_relation
      ).call
      @related_genre_lane = Public::Events::RelatedGenreLaneBuilder.new(
        event: @event,
        relation: show_related_genre_lane_events_relation
      ).call
    end

    def search_overlay
      @events =
        if @browse_state.search_query_present?
          visible_events_relation(
            scope: searchable_index_events_relation,
            filter: Public::Events::BrowseState::FILTER_ALL,
            event_date: @browse_state.event_date,
            query: @browse_state.query
          ).limit(SEARCH_OVERLAY_LIMIT).to_a
        else
          initial_search_overlay_events
        end

      render partial: "public/events/search_overlay",
             locals: {
               browse_state: @browse_state,
               events: @events,
               query: @browse_state.search_query_present? ? @browse_state.query : nil
             }
    end

    def status
      browse_state = Public::Events::BrowseState.new(params)
      @event = Event.find_by!(slug: params[:slug])
      desired_status = params[:status].to_s

      unless Event::STATUSES.include?(desired_status)
        redirect_back fallback_location: events_path(**browse_state.route_params(page: browse_state.page))
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
          redirect_back fallback_location: events_path(**browse_state.route_params(page: browse_state.page))
        end
      end
    end

    private

    def set_browse_state
      @browse_state = Public::Events::BrowseState.new(params)
    end

    def visible_events_relation(scope: index_events_relation, filter: Public::Events::BrowseState::FILTER_ALL, event_date: nil, query: nil)
      Public::VisibleEventsQuery.new(
        scope: scope,
        filter: filter,
        event_date: event_date,
        query: query
      ).call
    end

    def published_visible_events_relation(scope: published_future_events_relation, filter: Public::Events::BrowseState::FILTER_ALL, event_date: nil, query: nil)
      Public::VisibleEventsQuery.new(
        scope: scope,
        filter: filter,
        event_date: event_date,
        query: query
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
      return relation.where(status: "published").where("published_at <= ?", Time.current) unless authenticated?

      exclude_scheduled_published_events(relation)
    end

    def future_events_relation
      all_events_relation
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
      ).highlighted_first
      scoped_all = published_visible_events_relation(
        scope: homepage_events_relation,
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: @browse_state.event_date,
        query: nil
      )
      scoped_reservix = scoped_all.where(primary_source: "reservix")

      @home_featured_effective_series_ids = effective_public_series_ids_for_relation(scoped_highlights)
      @home_featured_events = Public::Events::SeriesRepresentativeSelector.call(scoped_highlights.to_a)

      if @home_featured_events.empty?
        fallback_relation = current_relation.reorder(:start_at, :id)
        @home_featured_effective_series_ids = effective_public_series_ids_for_relation(fallback_relation)
        @home_featured_events = Public::Events::SeriesRepresentativeSelector.call(fallback_relation.to_a)
      end

      @home_highlight_effective_series_ids = effective_public_series_ids_for_relation(scoped_reservix)
      @home_genre_lanes = Public::Events::HomepageGenreLanesBuilder.new(relation: homepage_events_relation).call
      @home_highlight_events = Public::Events::SeriesRepresentativeSelector.call(scoped_reservix.limit(HOME_HIGHLIGHT_LIMIT).to_a)
      tagestipp_scope = tagestipp_relation
      @home_tagestipp_effective_series_ids = effective_public_series_ids_for_relation(tagestipp_scope)
      @home_tagestipp_events = Public::Events::SeriesRepresentativeSelector.call(tagestipp_scope.to_a)
    end

    def should_redirect_search_result?(relation)
      return false unless @browse_state.search_query_present?
      return false unless @browse_state.page == 1

      relation.limit(2).count == 1
    end

    def published_events_relation
      all_events_relation
        .published_live
    end

    def homepage_events_relation
      Event.includes(
        :event_offers,
        :import_event_images,
        event_images: [ file_attachment: :blob ],
        event_presenters: { presenter: [ logo_attachment: :blob ] }
      ).published_live.where("start_at >= ?", Time.zone.today.beginning_of_day)
    end

    def search_events_relation
      Event.includes(
        :import_event_images,
        event_images: [ file_attachment: :blob ],
        event_presenters: { presenter: [ logo_attachment: :blob ] }
      )
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
        .where("published_at <= ?", Time.current)
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .chronological
    end

    def deduplicate_priority_events(*groups)
      groups.flatten.each_with_object({}) do |event, deduplicated_events|
        deduplicated_events[event.id] ||= event
      end.values
    end

    def search_filter
      return Public::Events::BrowseState::FILTER_ALL if @browse_state.search_query_present?

      @browse_state.filter
    end

    def show_events_relation
      return published_events_relation unless authenticated?

      all_events_relation
    end

    def show_related_genre_lane_events_relation
      Event.includes(
        :event_offers,
        :import_event_images,
        event_images: [ file_attachment: :blob ],
        event_presenters: { presenter: [ logo_attachment: :blob ] }
      ).published_live.where("start_at >= ?", Time.zone.today.beginning_of_day)
    end

    def show_event_series_lane_relation
      relation = Event.includes(
        :event_offers,
        :import_event_images,
        event_images: [ file_attachment: :blob ],
        event_presenters: { presenter: [ logo_attachment: :blob ] }
      )

      authenticated? ? relation : relation.published_live
    end

    def all_events_relation
      Event.includes(
        :llm_enrichment,
        :genres,
        :event_offers,
        :import_event_images,
        event_images: [ file_attachment: :blob ],
        event_presenters: { presenter: [ logo_attachment: :blob ] }
      )
    end

    def tagestipp_relation
      published_visible_events_relation(
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: Time.zone.today,
        query: nil
      )
        .where.not(primary_source: "reservix")
        .reorder(Arel.sql(sks_first_order_sql), :start_at, :id)
    end

    def exclude_scheduled_published_events(relation)
      events = Event.arel_table
      publicly_live = events[:status].eq("published").and(events[:published_at].lteq(Time.current))

      relation.where(events[:status].not_eq("published").or(publicly_live))
    end

    def sks_first_order_sql
      quoted_ids = Event.sks_promoter_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(", ")
      return "1" if quoted_ids.blank?

      "CASE WHEN events.promoter_id IN (#{quoted_ids}) THEN 0 ELSE 1 END"
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

    def render_not_found
      respond_to do |format|
      format.html do
          @browse_state ||= Public::Events::BrowseState.new(params)
          render "public/events/not_found", status: :not_found
        end
        format.any { head :not_found }
      end
    end
  end
end
