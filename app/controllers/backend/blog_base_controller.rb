module Backend
  class BlogBaseController < ApplicationController
    before_action :require_blog_access!

    private
      def require_blog_access!
        return if current_user&.blog_access?

        redirect_target = current_user&.backend_access? ? backend_root_path : root_path
        redirect_to redirect_target, alert: "Kein Zugriff auf das Blog-Backend."
      end
  end
end
