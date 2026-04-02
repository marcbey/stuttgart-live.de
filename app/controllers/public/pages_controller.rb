module Public
  class PagesController < ApplicationController
    allow_unauthenticated_access only: %i[show guardian_form]

    def show
      @page = StaticPage.with_page_content.find_by!(slug: params[:slug])
    end

    def guardian_form; end
  end
end
