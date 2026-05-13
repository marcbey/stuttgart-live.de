module Public
  class SitemapsController < ApplicationController
    allow_unauthenticated_access only: :show

    def show
      @entries = Public::Seo::SitemapBuilder.new(view_context: view_context).call
      expires_in 10.minutes, public: true
    end
  end
end
