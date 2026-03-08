module Backend
  class UsersController < BaseController
    before_action :require_admin!
    before_action :set_user, only: %i[edit update]

    def index
      @users = User.order(:role, :name, :email_address)
    end

    def new
      @user = User.new(role: "editor")
    end

    def create
      @user = User.new(user_create_params)

      if @user.save
        redirect_to backend_users_path, notice: "Benutzer wurde angelegt."
      else
        flash.now[:alert] = "Benutzer konnte nicht angelegt werden."
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      attributes = user_update_attributes
      password_changed = attributes.key?(:password)

      if @user.update(attributes)
        expire_sessions_for(@user) if password_changed
        redirect_to backend_users_path, notice: "Benutzer wurde aktualisiert."
      else
        flash.now[:alert] = "Benutzer konnte nicht aktualisiert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    private
      def set_user
        @user = User.find(params[:id])
      end

      def user_create_params
        params.require(:user).permit(:name, :email_address, :role, :password, :password_confirmation)
      end

      def user_update_attributes
        attributes = params.require(:user).permit(:name, :email_address, :role, :password, :password_confirmation).to_h.symbolize_keys
        attributes.except!(:password, :password_confirmation) if attributes[:password].blank?
        attributes.except!(:role) if @user == current_user
        attributes
      end

      def expire_sessions_for(user)
        if user == current_user
          user.sessions.where.not(id: Current.session.id).destroy_all
        else
          user.sessions.destroy_all
        end
      end
  end
end
