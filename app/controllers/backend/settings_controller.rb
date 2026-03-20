module Backend
  class SettingsController < BaseController
    before_action :require_admin!

    def edit
      @sks_promoter_ids_setting = AppSetting.sks_promoter_ids_record
      @sks_organizer_notes_setting = AppSetting.sks_organizer_notes_record
      @homepage_genre_lane_slugs_setting = AppSetting.homepage_genre_lane_slugs_record
      @llm_enrichment_model_setting = AppSetting.llm_enrichment_model_record
      @llm_enrichment_prompt_template_setting = AppSetting.llm_enrichment_prompt_template_record
      @llm_genre_grouping_model_setting = AppSetting.llm_genre_grouping_model_record
      @llm_genre_grouping_prompt_template_setting = AppSetting.llm_genre_grouping_prompt_template_record
      @llm_genre_grouping_group_count_setting = AppSetting.llm_genre_grouping_group_count_record
      @merge_artist_similarity_matching_setting = AppSetting.merge_artist_similarity_matching_enabled_record
      @homepage_genre_lane_reference_groups = homepage_genre_lane_reference_groups(@homepage_genre_lane_slugs_setting.homepage_genre_lane_slugs)
    end

    def update
      @sks_promoter_ids_setting = AppSetting.sks_promoter_ids_record
      @sks_promoter_ids_setting.sks_promoter_ids_text = settings_params[:sks_promoter_ids_text]
      @sks_organizer_notes_setting = AppSetting.sks_organizer_notes_record
      @sks_organizer_notes_setting.sks_organizer_notes_text = settings_params[:sks_organizer_notes_text]
      @homepage_genre_lane_slugs_setting = AppSetting.homepage_genre_lane_slugs_record
      @homepage_genre_lane_slugs_setting.homepage_genre_lane_slugs = settings_params.fetch(:homepage_genre_lane_slugs, [])
      @llm_enrichment_model_setting = AppSetting.llm_enrichment_model_record
      @llm_enrichment_model_setting.llm_enrichment_model = settings_params[:llm_enrichment_model]
      @llm_enrichment_prompt_template_setting = AppSetting.llm_enrichment_prompt_template_record
      @llm_enrichment_prompt_template_setting.llm_enrichment_prompt_template_text =
        settings_params[:llm_enrichment_prompt_template_text]
      @llm_genre_grouping_model_setting = AppSetting.llm_genre_grouping_model_record
      @llm_genre_grouping_model_setting.llm_genre_grouping_model = settings_params[:llm_genre_grouping_model]
      @llm_genre_grouping_prompt_template_setting = AppSetting.llm_genre_grouping_prompt_template_record
      @llm_genre_grouping_prompt_template_setting.llm_genre_grouping_prompt_template_text =
        settings_params[:llm_genre_grouping_prompt_template_text]
      @llm_genre_grouping_group_count_setting = AppSetting.llm_genre_grouping_group_count_record
      @llm_genre_grouping_group_count_setting.llm_genre_grouping_group_count =
        settings_params[:llm_genre_grouping_group_count]
      @merge_artist_similarity_matching_setting = AppSetting.merge_artist_similarity_matching_enabled_record
      @merge_artist_similarity_matching_setting.merge_artist_similarity_matching_enabled =
        settings_params[:merge_artist_similarity_matching_enabled]

      settings_records = [
        @sks_promoter_ids_setting,
        @sks_organizer_notes_setting,
        @homepage_genre_lane_slugs_setting,
        @llm_enrichment_model_setting,
        @llm_enrichment_prompt_template_setting,
        @llm_genre_grouping_model_setting,
        @llm_genre_grouping_prompt_template_setting,
        @llm_genre_grouping_group_count_setting,
        @merge_artist_similarity_matching_setting
      ]

      settings_are_valid = settings_records.map(&:valid?).all?

      if settings_are_valid
        AppSetting.transaction do
          settings_records.each(&:save!)
        end

        redirect_to edit_backend_settings_path, notice: "Einstellungen wurden gespeichert."
      else
        @homepage_genre_lane_reference_groups = homepage_genre_lane_reference_groups(@homepage_genre_lane_slugs_setting.homepage_genre_lane_slugs)
        flash.now[:alert] = "Einstellungen konnten nicht gespeichert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def settings_params
      params.require(:app_setting).permit(
        :sks_promoter_ids_text,
        :sks_organizer_notes_text,
        :llm_enrichment_model,
        :llm_enrichment_prompt_template_text,
        :llm_genre_grouping_model,
        :llm_genre_grouping_prompt_template_text,
        :llm_genre_grouping_group_count,
        :merge_artist_similarity_matching_enabled,
        homepage_genre_lane_slugs: []
      )
    end

    def homepage_genre_lane_reference_groups(selected_slugs = [])
      snapshot = LlmGenreGrouping::Lookup.active_snapshot
      return [] if snapshot.blank?

      upcoming_relation = Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day)
      selected_positions = Array(selected_slugs).each_with_index.to_h

      snapshot.groups.map do |group|
        {
          position: group.position,
          name: group.name,
          slug: group.slug,
          upcoming_events_count: LlmGenreGrouping::Lookup.events_for_group(group, relation: upcoming_relation).count
        }
      end.sort_by do |group|
        selection_index = selected_positions[group[:slug]]
        [
          selection_index.nil? ? 1 : 0,
          selection_index || group[:position],
          group[:position]
        ]
      end
    end
  end
end
