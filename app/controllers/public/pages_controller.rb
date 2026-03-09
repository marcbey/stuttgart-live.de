module Public
  class PagesController < ApplicationController
    allow_unauthenticated_access only: %i[contact imprint]

    def contact
    end

    def imprint
    end
  end
end
