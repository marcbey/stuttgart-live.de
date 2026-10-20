module Public
  class PagesController < ApplicationController
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
      @service_preview_highlight_events = service_preview_highlight_events
      @service_preview_effective_series_ids =
        Public::Events::EffectiveSeriesIdsQuery.call(@service_preview_highlight_events)
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

    def visible_events_relation(scope:, event_date:, query:, structured:)
      Public::VisibleEventsQuery.new(
        scope: scope,
        filter: Public::Events::BrowseState::FILTER_ALL,
        event_date: event_date,
        query: query,
        structured: structured
      ).call
    end

    def service_preview_events_relation
      Event.preload(
        :genres,
        :venue_record,
        :event_offers,
        :import_event_images,
        event_images: [ file_attachment: { blob: { variant_records: { image_attachment: :blob } } } ]
      )
        .published_live
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
    end
  end
end
