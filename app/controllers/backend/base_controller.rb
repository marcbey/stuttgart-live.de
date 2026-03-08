module Backend
  class BaseController < ApplicationController
    before_action :require_backend_access!

    private

    def require_backend_access!
      return if current_user&.backend_access?

      redirect_to root_path, alert: "Kein Zugriff auf das Backend."
    end

    def require_admin!
      return if current_user&.admin?

      redirect_to current_user&.backend_access? ? backend_root_path : root_path, alert: "Nur Admins dürfen Benutzer verwalten."
    end
  end
end
