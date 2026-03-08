module Backend
  class AccountPasswordsController < ApplicationController
    def edit
    end

    def update
      if current_user.update(password_params)
        current_user.sessions.where.not(id: Current.session.id).destroy_all
        redirect_to edit_backend_account_password_path, notice: "Passwort wurde aktualisiert."
      else
        flash.now[:alert] = "Passwort konnte nicht aktualisiert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    private
      def password_params
        params.require(:user).permit(:password, :password_confirmation)
      end
  end
end
