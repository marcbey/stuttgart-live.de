module Backend
  class BaseController < ApplicationController
    before_action :require_editor!

    private

    def require_editor!
      return if current_user&.admin? || current_user&.editor?

      redirect_to new_session_path, alert: "Bitte einloggen."
    end
  end
end
