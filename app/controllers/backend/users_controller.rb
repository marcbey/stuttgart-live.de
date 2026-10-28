module Backend
  class UsersController < BaseController
    before_action :require_admin!
    before_action :set_user, only: %i[edit update destroy]

    def index
      @users = User.order(:role, :name, :email_address)
      @admin_count = @users.count(&:admin?)
    end

    def new
      @user = User.new(role: "editor")
    end

    def create
      @user = User.new(user_attributes)
      assign_requested_role(@user)

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
      attributes = user_attributes.to_h.symbolize_keys
      attributes.except!(:password, :password_confirmation) if attributes[:password].blank?
      password_changed = attributes.key?(:password)
      @user.assign_attributes(attributes)
      assign_requested_role(@user) unless @user == current_user

      if @user.save
        expire_sessions_for(@user) if password_changed
        redirect_to backend_users_path, notice: "Benutzer wurde aktualisiert."
      else
        flash.now[:alert] = "Benutzer konnte nicht aktualisiert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      deleting_self = @user == current_user

      if @user.destroy
        if deleting_self
          cookies.delete(:session_id)
          Current.session = nil
        end

        redirect_to deleting_self ? new_session_path : backend_users_path,
                    notice: "Benutzer wurde gelöscht.", status: :see_other
      else
        redirect_to backend_users_path, alert: @user.errors.full_messages.to_sentence, status: :see_other
      end
    rescue ActiveRecord::DeleteRestrictionError
      redirect_to backend_users_path,
                  alert: "Benutzer mit eigenen Blogbeiträgen können nicht gelöscht werden.", status: :see_other
    end

    private
      def set_user
        @user = User.find(params[:id])
      end

      def user_attributes
        params.require(:user).permit(:name, :email_address, :password, :password_confirmation)
      end

      def requested_role
        params.dig(:user, :role).to_s.strip.presence
      end

      def assign_requested_role(user)
        return if requested_role.blank?

        user.role = requested_role
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
