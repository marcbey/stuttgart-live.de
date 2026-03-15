module Backend
  class SettingsController < BaseController
    before_action :require_admin!

    def edit
      @app_setting = AppSetting.sks_promoter_ids_record
    end

    def update
      @app_setting = AppSetting.sks_promoter_ids_record
      @app_setting.sks_promoter_ids_text = settings_params[:sks_promoter_ids_text]

      if @app_setting.save
        redirect_to edit_backend_settings_path, notice: "Einstellungen wurden gespeichert."
      else
        flash.now[:alert] = "Einstellungen konnten nicht gespeichert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def settings_params
      params.require(:app_setting).permit(:sks_promoter_ids_text)
    end
  end
end
