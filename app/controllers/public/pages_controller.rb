module Public
  class PagesController < ApplicationController
    allow_unauthenticated_access only: %i[privacy imprint terms contact]

    def privacy; end

    def imprint; end

    def terms; end

    def contact; end
  end
end
