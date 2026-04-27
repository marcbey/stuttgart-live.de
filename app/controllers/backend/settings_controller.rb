module Backend
  class SettingsController < BaseController
    DEFAULT_SECTION = "meta_connection".freeze

    SECTIONS = [
      {
        key: "meta_connection",
        label: "Meta Publishing",
        panel_id: "settings-panel-meta-connection",
        tab_id: "settings-tab-meta-connection",
        partial: "backend/settings/sections/meta_connection"
      },
      {
        key: "sks_promoter_ids",
        label: "SKS Promoter IDs",
        panel_id: "settings-panel-sks-promoter-ids",
        tab_id: "settings-tab-sks-promoter-ids",
        partial: "backend/settings/sections/sks_promoter_ids"
      },
      {
        key: "sks_organizer_notes",
        label: "SKS Standard-Veranstalterhinweise",
        panel_id: "settings-panel-sks-organizer-notes",
        tab_id: "settings-tab-sks-organizer-notes",
        partial: "backend/settings/sections/sks_organizer_notes"
      },
      {
        key: "homepage_genre_lanes",
        label: "Homepage Genre-Lanes",
        panel_id: "settings-panel-homepage-genre-lanes",
        tab_id: "settings-tab-homepage-genre-lanes",
        partial: "backend/settings/sections/homepage_genre_lanes"
      },
      {
        key: "llm_enrichment",
        label: "LLM-Enrichment",
        panel_id: "settings-panel-llm-enrichment",
        tab_id: "settings-tab-llm-enrichment",
        partial: "backend/settings/sections/llm_enrichment"
      },
      {
        key: "llm_genre_grouping",
        label: "LLM-Genre-Gruppierung",
        panel_id: "settings-panel-llm-genre-grouping",
        tab_id: "settings-tab-llm-genre-grouping",
        partial: "backend/settings/sections/llm_genre_grouping"
      },
      {
        key: "merge_artist_similarity_matching",
        label: "Ähnlichkeits-Matching",
        panel_id: "settings-panel-merge-artist-similarity-matching",
        tab_id: "settings-tab-merge-artist-similarity-matching",
        partial: "backend/settings/sections/merge_artist_similarity_matching"
      }
    ].freeze

    before_action :require_admin!
    before_action :set_active_section
    before_action :load_active_section, only: [ :edit, :section ]

    helper_method :settings_sections, :active_settings_section, :active_section_records, :section_loaded?

    def edit
    end

    def section
      render partial: active_settings_section.fetch(:partial), locals: section_render_locals
    end

    def update
      load_active_section
      assign_active_section_attributes

      section_is_valid = active_section_records.map(&:valid?).all?

      if section_is_valid
        AppSetting.transaction do
          active_section_records.each(&:save!)
        end

        redirect_to active_section_redirect_path, notice: "Einstellungen wurden gespeichert."
      else
        flash.now[:alert] = "Einstellungen konnten nicht gespeichert werden."
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def settings_sections
      SECTIONS
    end

    def active_settings_section
      @active_settings_section
    end

    def section_loaded?(section_key)
      section_key.to_s == @active_section_key
    end

    def set_active_section
      @active_section_key = normalized_section_key(params[:section])
      @active_settings_section = settings_sections.find { |section| section.fetch(:key) == @active_section_key }
    end

    def normalized_section_key(raw_key)
      key = raw_key.to_s
      settings_sections.any? { |section| section.fetch(:key) == key } ? key : DEFAULT_SECTION
    end

    def load_active_section
      case @active_section_key
      when "meta_connection"
        resolver = Meta::ConnectionResolver.new
        @instagram_connection = resolver.instagram_connection
        @facebook_connection = resolver.facebook_connection
        @instagram_access_status = Meta::AccessStatus.new(platform: "instagram").call
        @facebook_access_status = Meta::AccessStatus.new(platform: "facebook").call
      when "sks_promoter_ids"
        @sks_promoter_ids_setting = AppSetting.sks_promoter_ids_record
      when "sks_organizer_notes"
        @sks_organizer_notes_setting = AppSetting.sks_organizer_notes_record
      when "homepage_genre_lanes"
        @public_genre_grouping_snapshot_id_setting = AppSetting.public_genre_grouping_snapshot_id_record
        @homepage_genre_lane_snapshots = LlmGenreGroupingSnapshot.recent_first.includes(:groups, :homepage_genre_lane_configuration).to_a
        @homepage_selected_snapshot = homepage_selected_snapshot
        @homepage_distinct_llm_genres = homepage_distinct_llm_genres
        @homepage_distinct_llm_genres_text = @homepage_distinct_llm_genres.join(", ")
        @homepage_genre_lane_configuration =
          @homepage_selected_snapshot&.homepage_genre_lane_configuration || @homepage_selected_snapshot&.build_homepage_genre_lane_configuration
        @homepage_genre_lane_reference_groups =
          homepage_genre_lane_reference_groups(@homepage_selected_snapshot, @homepage_genre_lane_configuration&.lane_slugs)
      when "llm_enrichment"
        @llm_enrichment_model_setting = AppSetting.llm_enrichment_model_record
        @llm_enrichment_prompt_template_setting = AppSetting.llm_enrichment_prompt_template_record
        @llm_enrichment_temperature_setting = AppSetting.llm_enrichment_temperature_record
        @llm_enrichment_web_search_provider_setting = AppSetting.llm_enrichment_web_search_provider_record
      when "llm_genre_grouping"
        @llm_genre_grouping_model_setting = AppSetting.llm_genre_grouping_model_record
        @llm_genre_grouping_prompt_template_setting = AppSetting.llm_genre_grouping_prompt_template_record
        @llm_genre_grouping_group_count_setting = AppSetting.llm_genre_grouping_group_count_record
      when "merge_artist_similarity_matching"
        @merge_artist_similarity_matching_setting = AppSetting.merge_artist_similarity_matching_enabled_record
      end
    end

    def assign_active_section_attributes
      case @active_section_key
      when "sks_promoter_ids"
        @sks_promoter_ids_setting.sks_promoter_ids_text = active_settings_params[:sks_promoter_ids_text]
      when "sks_organizer_notes"
        @sks_organizer_notes_setting.sks_organizer_notes_text = active_settings_params[:sks_organizer_notes_text]
      when "homepage_genre_lanes"
        @public_genre_grouping_snapshot_id_setting.public_genre_grouping_snapshot_id =
          active_settings_params[:public_genre_grouping_snapshot_id]
        @homepage_genre_lane_configuration&.lane_slugs = active_settings_params.fetch(:homepage_genre_lane_slugs, [])
      when "llm_enrichment"
        @llm_enrichment_model_setting.llm_enrichment_model = active_settings_params[:llm_enrichment_model]
        @llm_enrichment_prompt_template_setting.llm_enrichment_prompt_template_text =
          active_settings_params[:llm_enrichment_prompt_template_text]
        @llm_enrichment_temperature_setting.llm_enrichment_temperature =
          active_settings_params[:llm_enrichment_temperature]
        @llm_enrichment_web_search_provider_setting.llm_enrichment_web_search_provider =
          active_settings_params[:llm_enrichment_web_search_provider]
      when "llm_genre_grouping"
        @llm_genre_grouping_model_setting.llm_genre_grouping_model = active_settings_params[:llm_genre_grouping_model]
        @llm_genre_grouping_prompt_template_setting.llm_genre_grouping_prompt_template_text =
          active_settings_params[:llm_genre_grouping_prompt_template_text]
        @llm_genre_grouping_group_count_setting.llm_genre_grouping_group_count =
          active_settings_params[:llm_genre_grouping_group_count]
      when "merge_artist_similarity_matching"
        @merge_artist_similarity_matching_setting.merge_artist_similarity_matching_enabled =
          active_settings_params[:merge_artist_similarity_matching_enabled]
      end
    end

    def active_section_records
      case @active_section_key
      when "meta_connection"
        []
      when "sks_promoter_ids"
        [ @sks_promoter_ids_setting ]
      when "sks_organizer_notes"
        [ @sks_organizer_notes_setting ]
      when "homepage_genre_lanes"
        [ @public_genre_grouping_snapshot_id_setting, @homepage_genre_lane_configuration ].compact
      when "llm_enrichment"
        [
          @llm_enrichment_model_setting,
          @llm_enrichment_prompt_template_setting,
          @llm_enrichment_temperature_setting,
          @llm_enrichment_web_search_provider_setting
        ]
      when "llm_genre_grouping"
        [
          @llm_genre_grouping_model_setting,
          @llm_genre_grouping_prompt_template_setting,
          @llm_genre_grouping_group_count_setting
        ]
      when "merge_artist_similarity_matching"
        [ @merge_artist_similarity_matching_setting ]
      else
        []
      end
    end

    def active_settings_params
      case @active_section_key
      when "meta_connection"
        ActionController::Parameters.new.permit!
      when "sks_promoter_ids"
        params.require(:app_setting).permit(:sks_promoter_ids_text)
      when "sks_organizer_notes"
        params.require(:app_setting).permit(:sks_organizer_notes_text)
      when "homepage_genre_lanes"
        params.require(:app_setting).permit(:public_genre_grouping_snapshot_id, homepage_genre_lane_slugs: [])
      when "llm_enrichment"
        params.require(:app_setting).permit(
          :llm_enrichment_model,
          :llm_enrichment_prompt_template_text,
          :llm_enrichment_temperature,
          :llm_enrichment_web_search_provider
        )
      when "llm_genre_grouping"
        params.require(:app_setting).permit(
          :llm_genre_grouping_model,
          :llm_genre_grouping_prompt_template_text,
          :llm_genre_grouping_group_count
        )
      when "merge_artist_similarity_matching"
        params.require(:app_setting).permit(:merge_artist_similarity_matching_enabled)
      else
        ActionController::Parameters.new.permit!
      end
    end

    def section_render_locals
      {
        section_key: @active_section_key,
        section_definition: active_settings_section,
        settings_records: active_section_records
      }
    end

    def active_section_redirect_path
      return edit_backend_settings_path(section: @active_section_key, selected_snapshot_id: @homepage_selected_snapshot&.id) if @active_section_key == "homepage_genre_lanes"

      edit_backend_settings_path(section: @active_section_key)
    end

    def homepage_selected_snapshot
      snapshot_id = selected_homepage_snapshot_id
      return if snapshot_id.blank?

      @homepage_genre_lane_snapshots.find { |snapshot| snapshot.id == snapshot_id }
    end

    def selected_homepage_snapshot_id
      AppSetting.normalize_positive_integer(params[:selected_snapshot_id].presence || params.dig(:app_setting, :public_genre_grouping_snapshot_id).presence) ||
        AppSetting.public_genre_grouping_snapshot_id
    end

    def homepage_genre_lane_reference_groups(snapshot, selected_slugs = [])
      return [] if snapshot.blank?

      upcoming_relation = Event.published_live.where("start_at >= ?", Time.zone.today.beginning_of_day)
      selected_positions = Array(selected_slugs).each_with_index.to_h

      snapshot.groups.map do |group|
        member_genres = homepage_genre_group_member_genres(group)

        {
          position: group.position,
          name: group.name,
          slug: group.slug,
          upcoming_events_count: LlmGenreGrouping::Lookup.events_for_group(group, relation: upcoming_relation).count,
          member_genres_text: "#{group.name}: #{member_genres.join(', ')}",
          member_genres_tooltip: homepage_genre_group_member_genres_tooltip(member_genres)
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

    def homepage_genre_group_member_genres(group)
      Array(group.member_genres).filter_map do |entry|
        value = entry.to_s.strip
        value.presence
      end.uniq
    end

    def homepage_genre_group_member_genres_tooltip(member_genres)
      return if member_genres.empty?

      "Enthaltene Genres: #{member_genres.join(', ')}"
    end

    def homepage_distinct_llm_genres
      EventLlmEnrichment.pluck(:genre)
        .flatten
        .compact
        .map(&:to_s)
        .map(&:strip)
        .reject(&:blank?)
        .uniq
        .sort
    end
  end
end
