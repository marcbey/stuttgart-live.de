class ErrorsController < ActionController::Base
  include Authentication

  layout "application"
  allow_unauthenticated_access only: :show

  ERROR_COPY = {
    400 => {
      eyebrow: "Ungültige Anfrage",
      title: "Diese Anfrage passt nicht.",
      message: "Die Seite konnte mit diesen Angaben nicht verarbeitet werden. Geh zurück und versuch es noch einmal."
    },
    404 => {
      eyebrow: "Nicht gefunden",
      title: "Diese Seite gibt es nicht.",
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
    render :show, status: @status_code
  end

  private

  def requested_status_code
    raw_status = params[:code].presence || request.path.delete_prefix("/")
    Integer(raw_status, exception: false).presence_in(ERROR_COPY.keys) || 500
  end
end
