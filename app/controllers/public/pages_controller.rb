module Public
  class PagesController < ApplicationController
    SEARCH_OVERLAY_LIMIT = 6
    SEARCH_OVERLAY_IDLE_LIMIT = 10

    allow_unauthenticated_access only: %i[show guardian_form design_preview_service]
    before_action :set_browse_state, only: %i[show design_preview_service]

    def show
      @page = StaticPage.with_page_content.find_by!(slug: params[:slug])
      assign_design_service_preview

      render :design_preview_service
    end

    def guardian_form; end

    def design_preview_service
      @page = StaticPage.with_page_content.find_by(system_key: "privacy") ||
              StaticPage.with_page_content.find_by(slug: "datenschutz")
      assign_design_service_preview
    end

    private

    def set_browse_state
      @browse_state = Public::Events::BrowseState.new(params)
    end

    def assign_design_service_preview
      @design_preview_search_overlay = build_search_overlay
      @service_preview_genre_lanes = service_preview_genre_lanes
      @service_preview_highlight_events = service_preview_highlight_events
      @service_preview_effective_series_ids =
        Public::Events::EffectiveSeriesIdsQuery.call(@service_preview_highlight_events)
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
        scope: service_preview_search_relation,
        event_date: @browse_state.event_date,
        query: @browse_state.query,
        structured: structured
      ).limit(SEARCH_OVERLAY_LIMIT).to_a
    end

    def initial_search_overlay_events
      promotion_events = initial_search_overlay_events_for(service_preview_search_relation.where(promotion_banner: true))
      highlighted_events = initial_search_overlay_events_for(service_preview_search_relation.where(highlighted: true))
      sks_events = initial_search_overlay_events_for(service_preview_search_relation.merge(Event.sks_promoters))

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

    def service_preview_highlight_events
      selected_events = visible_events_relation(
        scope: service_preview_events_relation.homepage_highlights,
        event_date: @browse_state.event_date,
        query: nil,
        structured: true
      ).limit(24).to_a

      Public::Events::SeriesRepresentativeSelector.call(selected_events).first(7)
    end

    def service_preview_genre_lanes
      Public::Events::HomepageGenreLanesBuilder.new(
        relation: service_preview_events_relation,
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

    def service_preview_search_relation
      service_preview_events_relation.search_priority_first
    end

    def service_preview_events_relation
      Event.includes(
        :venue_record,
        :event_offers,
        :import_event_images,
        event_images: [ file_attachment: :blob ]
      )
        .published_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
    end
  end
end
