module Backend
  class SettingsController < BaseController
    before_action :require_admin!

    def edit
      @sks_promoter_ids_setting = AppSetting.sks_promoter_ids_record
      @sks_organizer_notes_setting = AppSetting.sks_organizer_notes_record
      @llm_enrichment_prompt_template_setting = AppSetting.llm_enrichment_prompt_template_record
      @merge_artist_similarity_matching_setting = AppSetting.merge_artist_similarity_matching_enabled_record
    end

    def update
      @sks_promoter_ids_setting = AppSetting.sks_promoter_ids_record
      @sks_promoter_ids_setting.sks_promoter_ids_text = settings_params[:sks_promoter_ids_text]
      @sks_organizer_notes_setting = AppSetting.sks_organizer_notes_record
      @sks_organizer_notes_setting.sks_organizer_notes_text = settings_params[:sks_organizer_notes_text]
      @llm_enrichment_prompt_template_setting = AppSetting.llm_enrichment_prompt_template_record
      @llm_enrichment_prompt_template_setting.llm_enrichment_prompt_template_text =
        settings_params[:llm_enrichment_prompt_template_text]
      @merge_artist_similarity_matching_setting = AppSetting.merge_artist_similarity_matching_enabled_record
      @merge_artist_similarity_matching_setting.merge_artist_similarity_matching_enabled =
        settings_params[:merge_artist_similarity_matching_enabled]

      if @sks_promoter_ids_setting.valid? &&
          @sks_organizer_notes_setting.valid? &&
          @llm_enrichment_prompt_template_setting.valid? &&
          @merge_artist_similarity_matching_setting.valid?
        AppSetting.transaction do
          @sks_promoter_ids_setting.save!
          @sks_organizer_notes_setting.save!
          @llm_enrichment_prompt_template_setting.save!
          @merge_artist_similarity_matching_setting.save!
        end

        redirect_to edit_backend_settings_path, notice: "Einstellungen wurden gespeichert."
      else
        flash.now[:alert] = "Einstellungen konnten nicht gespeichert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def settings_params
      params.require(:app_setting).permit(
        :sks_promoter_ids_text,
        :sks_organizer_notes_text,
        :llm_enrichment_prompt_template_text,
        :merge_artist_similarity_matching_enabled
      )
    end
  end
end
