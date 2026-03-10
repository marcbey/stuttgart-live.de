module Public
  class PagesController < ApplicationController
    allow_unauthenticated_access only: %i[privacy imprint terms contact accessibility guardian_form]

    def privacy; end

    def imprint; end

    def terms; end

    def contact; end

    def accessibility; end

    def guardian_form; end
  end
end
