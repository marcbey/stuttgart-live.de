module Backend
  class PresentersController < BaseController
    before_action :set_presenter, only: [ :edit, :update, :destroy ]

    def index
      @presenters = Presenter.with_attached_logo.includes(:event_presenters).ordered_by_name
    end

    def new
      @presenter = Presenter.new
    end

    def bulk_new
      @bulk_import_result = nil
    end

    def create
      @presenter = Presenter.new(presenter_params)

      if @presenter.save
        redirect_to backend_presenters_path, notice: "Präsentator wurde angelegt."
      else
        flash.now[:alert] = "Präsentator konnte nicht angelegt werden."
        render :new, status: :unprocessable_entity
      end
    end

    def bulk_create
      @bulk_import_result = Backend::Presenters::BulkImporter.new(files: bulk_upload_files).call

      if @bulk_import_result.total_processed.zero?
        flash.now[:alert] = "Bitte mindestens eine Datei auswählen."
        render :bulk_new, status: :unprocessable_entity
      elsif @bulk_import_result.any_errors?
        flash.now[:alert] = "Einige Logos konnten nicht importiert werden."
        render :bulk_new, status: :unprocessable_entity
      else
        redirect_to backend_presenters_path, notice: bulk_import_notice
      end
    end

    def edit
    end

    def update
      if @presenter.update(presenter_params)
        redirect_to backend_presenters_path, notice: "Präsentator wurde aktualisiert."
      else
        flash.now[:alert] = "Präsentator konnte nicht aktualisiert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @presenter.event_presenters.exists?
        redirect_to backend_presenters_path, alert: "Präsentator ist noch Events zugeordnet und kann nicht gelöscht werden."
        return
      end

      if @presenter.destroy
        redirect_to backend_presenters_path, notice: "Präsentator wurde gelöscht."
      else
        redirect_to backend_presenters_path, alert: @presenter.errors.full_messages.to_sentence.presence || "Präsentator konnte nicht gelöscht werden."
      end
    end

    private

    def set_presenter
      @presenter = Presenter.with_attached_logo.find(params[:id])
    end

    def presenter_params
      params.require(:presenter).permit(:name, :description, :external_url, :logo)
    end

    def bulk_upload_files
      params.permit(presenter_logos: [], presenter_directory_logos: []).values.flatten.compact_blank
    end

    def bulk_import_notice
      parts = []
      parts << "#{@bulk_import_result.created} neu angelegt" if @bulk_import_result.created.positive?
      parts << "#{@bulk_import_result.updated} aktualisiert" if @bulk_import_result.updated.positive?
      "Logo-Import abgeschlossen: #{parts.to_sentence}."
    end
  end
end
