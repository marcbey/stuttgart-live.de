module Backend
  class PagesController < BaseController
    before_action :set_page, only: %i[edit update destroy]

    def index
      @pages = StaticPage.with_page_content.order(:title, :id)
    end

    def new
      @page = StaticPage.new
    end

    def create
      @page = StaticPage.new(page_params)

      if @page.save
        redirect_to edit_backend_page_path(@page), notice: "Seite wurde angelegt."
      else
        flash.now[:alert] = "Seite konnte nicht angelegt werden."
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @page.update(page_params)
        redirect_to edit_backend_page_path(@page), notice: "Seite wurde gespeichert."
      else
        flash.now[:alert] = "Seite konnte nicht gespeichert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @page.destroy
        redirect_to backend_pages_path, notice: "Seite wurde gelöscht."
      else
        redirect_to backend_pages_path, alert: @page.errors.full_messages.to_sentence.presence || "Seite konnte nicht gelöscht werden."
      end
    end

    private
      def set_page
        @page = StaticPage.with_page_content.find(params[:id])
      end

      def page_params
        params.require(:static_page).permit(:slug, :title, :kicker, :intro, :body)
      end
  end
end
