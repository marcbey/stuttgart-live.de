class ErrorsController < ActionController::Base
  include Authentication

  layout "public_error"
  allow_unauthenticated_access only: :show

  ERROR_COPY = {
    400 => {
      eyebrow: "Ungültige Anfrage",
      title: "Diese Anfrage passt nicht.",
      message: "Die Seite konnte mit diesen Angaben nicht verarbeitet werden. Geh zurück und versuch es noch einmal."
    },
    404 => {
      eyebrow: "Nicht gefunden",
      title: "Ups! Diese Seite gibt es leider nicht.",
      message: "Der Link führt ins Leere oder die Seite ist nicht mehr verfügbar."
    },
    422 => {
      eyebrow: "Nicht verarbeitet",
      title: "Das hat nicht funktioniert.",
      message: "Die Anfrage konnte nicht verarbeitet werden. Prüf die Eingaben und versuch es erneut."
    },
    500 => {
      eyebrow: "Serverfehler",
      title: "Beim Laden ist etwas schiefgelaufen.",
      message: "Auf unserer Seite ist ein Fehler passiert. Versuch es in einem Moment noch einmal."
    }
  }.freeze

  def show
    @status_code = requested_status_code
    @error_copy = ERROR_COPY.fetch(@status_code, ERROR_COPY[500])
    if @status_code == 404 && request.get? && request.format.html? && (page = public_not_found_page)
      return render body: page, content_type: "text/html", status: :not_found
    end

    render :show, formats: [ :html ], status: @status_code
  end

  private

  def public_not_found_page
    @browse_state = Public::Events::BrowseState.new({})
    @not_found_events = Public::Events::SeriesRepresentativeSelector.call(
      Event.published_live.homepage_highlights
        .where("start_at >= ?", Time.zone.today.beginning_of_day)
        .includes(
          :venue_record, :event_offers, :genres, :import_event_images,
          event_images: [ file_attachment: { blob: { variant_records: { image_attachment: :blob } } } ]
        ).limit(24).to_a
    ).first(6)
    @effective_series_ids = Public::Events::EffectiveSeriesIdsQuery.call(@not_found_events)
    @series_counts_by_id = Public::Events::SeriesCountsByIdQuery.call(@not_found_events)
    @search_overlay = Public::Events::Search::OverlayBuilder::Result.new(
      mode: :idle, query: nil, events: @not_found_events, suggestions: [], venues: [], genres: []
    )

    render_to_string "errors/not_found", layout: "public_not_found", formats: [ :html ]
  rescue StandardError => error
    # The recovery page must still render when its optional content is unavailable.
    Rails.logger.warn("404 content unavailable: #{error.class}: #{error.message}")
    Rails.error.report(error, handled: true, context: { component: "public_not_found_page" })
    nil
  end

  def requested_status_code
    raw_status = params[:code].presence || request.path.delete_prefix("/")
    Integer(raw_status, exception: false).presence_in(ERROR_COPY.keys) || 500
  end
end
