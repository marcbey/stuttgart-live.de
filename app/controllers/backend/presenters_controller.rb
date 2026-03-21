module Backend
  class PresentersController < BaseController
    before_action :set_presenter, only: [ :edit, :update, :destroy ]

    def index
      @presenters = Presenter.with_attached_logo.includes(:event_presenters).ordered_by_name
    end

    def new
      @presenter = Presenter.new
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
  end
end
