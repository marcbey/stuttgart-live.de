module Backend
  class EventsController < BaseController
    MANUAL_EVENT_PROMOTER_ID = "382".freeze
    MANUAL_EVENT_PROMOTER_NAME = "RUSS Live".freeze

    before_action :set_event, only: [ :show, :update, :publish, :unpublish, :run_llm_enrichment ]
    before_action :set_available_merge_runs
    before_action :set_inbox_state
    before_action :set_next_event_enabled, only: [ :index, :show, :new, :create, :update, :publish, :unpublish, :run_llm_enrichment ]
    before_action :load_all_genres, only: [ :index, :show, :new, :create, :update, :unpublish, :run_llm_enrichment ]
    before_action :load_all_presenters, only: [ :index, :show, :new, :create, :update, :unpublish, :run_llm_enrichment ]

    def index
      prepare_index_state!
      @active_editor_tab = new_panel_requested? ? new_editor_tab : "event"
      @selected_event = selected_event_from(@events)
    end

    def apply_filters
      @inbox_state.persist_filters!
      redirect_to backend_events_path(status: @inbox_state.current_status)
    end

    def next_event_preference
      @next_event_enabled = @inbox_state.persist_next_event_preference!(params[:enabled])
      head :ok
    end

    def show
      @filter_status = @inbox_state.navigation_status || params[:status].to_s.presence_in(status_filters)
      @active_editor_tab = editor_tab_for(@event)
    end

    def new
      prepare_new_event_state!

      return render_new_editor_frame if turbo_frame_request?

      redirect_to backend_events_path(
        status: @inbox_state.current_status,
        new: "1",
        editor_tab: new_editor_tab_param
      )
    end

    def create
      @event = Event.new(event_attribute_params.merge(manual_event_promoter_attributes))
      prepare_promotion_banner_image(@event)
      @selected_genre_ids = genre_ids_from_params
      @selected_presenter_ids = presenter_ids_from_params
      @manual_image_form_values = manual_image_form_values
      @manual_ticket_url = manual_ticket_url
      @manual_ticket_sold_out = manual_ticket_sold_out
      @active_editor_tab = new_editor_tab
      created_images = []
      creation_alert = nil

      set_publishing_fields!(@event)
      validate_manual_ticket_url!(@event)

      Event.transaction do
        unless @event.errors.empty? && @event.save
          creation_alert = "Event konnte nicht erstellt werden."
          raise ActiveRecord::Rollback
        end

        sync_venue_from_llm_fallback!(@event)
        persist_promotion_banner_image!(@event)

        assign_genres!(@event)
        sync_presenters!(@event)
        create_manual_ticket_offer!(@event)
        created_images = attach_manual_event_images!
        refresh_completeness!(@event)
        Editorial::EventChangeLogger.log!(
          event: @event,
          action: "created",
          user: current_user,
          changed_fields: @event.saved_changes
        )
      rescue ActiveRecord::RecordInvalid => e
        creation_alert = e.record.errors.full_messages.to_sentence
        raise ActiveRecord::Rollback
      rescue EventImage::ProcessingError => e
        creation_alert = e.message
        raise ActiveRecord::Rollback
      rescue ArgumentError => e
        creation_alert = e.message
        raise ActiveRecord::Rollback
      end

      created_successfully = creation_alert.blank? && @event.id.present? && Event.exists?(@event.id)

      if created_successfully
        begin
          created_images.each(&:processed_optimized_variant)
        rescue EventImage::ProcessingError => e
          creation_alert = e.message
          @event.destroy! if @event.persisted?
          @event = Event.new(event_attribute_params.merge(manual_event_promoter_attributes))
          created_successfully = false
        end
      end

      if !created_successfully
        flash.now[:alert] = creation_alert || "Event konnte nicht erstellt werden."
        prepare_index_state!
        @selected_event = @event
        render :index, status: :unprocessable_entity
      else
        redirect_to backend_events_path(status: @event.status, event_id: @event.id), notice: "Event wurde erstellt."
      end
    end

    def update
      @next_event_enabled = @inbox_state.persist_next_event_preference!(params[:next_event_enabled]) if params.key?(:next_event_enabled)
      navigation_status = @inbox_state.navigation_status
      @manual_ticket_url = manual_ticket_url
      @manual_ticket_sold_out = manual_ticket_sold_out
      previous_venue_id = @event.venue_id

      @event.assign_attributes(event_attribute_params)
      prepare_promotion_banner_image(@event)
      @event.status = "published" if save_and_publish_requested?
      set_publishing_fields!(@event)
      validate_manual_ticket_url!(@event)

      if @event.errors.any?
        editor_response.validation_error(
          event: @event,
          filter_status: navigation_status || @event.status,
          active_editor_tab: editor_tab_for(@event)
        )
      elsif @event.save
        sync_venue_from_llm_fallback!(@event)
        persist_promotion_banner_image!(@event)
        begin
          update_detail_hero_crop!
          update_slider_image_metadata!
          sync_presenters!(@event)
        rescue ActiveRecord::RecordInvalid => e
          @event.errors.add(:base, e.record.errors.full_messages.to_sentence)
          editor_response.validation_error(
            event: @event,
            filter_status: navigation_status || @event.status,
            active_editor_tab: editor_tab_for(@event)
          )
          return
        end

        sync_ticket_offer!(@event)
        assign_genres!(@event) if params[:event].respond_to?(:key?) && params[:event].key?(:genre_ids)
        refresh_completeness!(@event)
        Editorial::EventChangeLogger.log!(
          event: @event,
          action: "updated",
          user: current_user,
          changed_fields: @event.saved_changes
        )

        editor_state = build_editor_state_builder.build(preferred_event: @event, navigation_status: navigation_status)

        editor_response.success(
          editor_state: editor_state,
          notice: update_success_message(previous_venue_id: previous_venue_id),
          active_editor_tab: editor_tab_for_success(target_event: editor_state.target_event)
        )
      else
        editor_response.validation_error(
          event: @event,
          filter_status: navigation_status || @event.status,
          active_editor_tab: editor_tab_for(@event)
        )
      end
    end

    def publish
      @event.publish!(user: current_user, auto_published: false)
      Editorial::EventChangeLogger.log!(event: @event, action: "published", user: current_user)
      redirect_to backend_events_path(status: "published", event_id: @event.id), notice: "Event wurde veröffentlicht."
    end

    def unpublish
      navigation_status = @inbox_state.navigation_status
      @event.unpublish!(status: "ready_for_publish", auto_published: false)
      Editorial::EventChangeLogger.log!(event: @event, action: "unpublished", user: current_user)
      editor_response.success(
        editor_state: build_editor_state_builder.build(
          preferred_event: @event,
          navigation_status: navigation_status
        ),
        notice: "Event wurde depublisht.",
        active_editor_tab: "event"
      )
    end

    def run_llm_enrichment
      result = llm_run_enqueuer.call(
        source_type: "llm_enrichment",
        import_source: llm_enrichment_run_source,
        run_metadata: single_event_llm_enrichment_run_metadata(@event)
      )

      if result.alert.present?
        respond_with_llm_enrichment_feedback(alert: result.alert)
        return
      end

      notice =
        if result.dispatched
          "LLM-Enrichment für dieses Event wurde gestartet."
        else
          llm_enrichment_queue_notice(queue_position: result.queue_position)
        end

      respond_with_llm_enrichment_feedback(notice:)
    end

    def bulk
      event_ids = Array(params[:event_ids]).map(&:to_i).uniq
      action = params[:bulk_action].to_s

      if event_ids.blank?
        redirect_to backend_events_path(status: @inbox_state.current_status), alert: "Bitte mindestens ein Event auswählen."
        return
      end

      events = Event.where(id: event_ids)
      processed = Backend::Events::BulkUpdater.new(events: events, action: action, user: current_user).call

      redirect_to backend_events_path(status: @inbox_state.current_status), notice: "Bulk-Aktion abgeschlossen (#{processed} Events)."
    end

    private

    def set_inbox_state
      @inbox_state = Backend::Events::InboxState.new(
        params: params,
        session: session,
        status_filters: status_filters,
        available_merge_run_ids: @available_merge_runs.map(&:id),
        latest_successful_merge_run_id: @available_merge_runs.first&.id
      )
    end

    def set_available_merge_runs
      @available_merge_runs = available_merge_runs
    end

    def set_event
      @event = Event.includes(
        :llm_enrichment,
        :import_event_images,
        :venue_record,
        promotion_banner_image_attachment: :blob,
        event_images: [ file_attachment: :blob ],
        event_presenters: { presenter: [ logo_attachment: :blob ] }
      ).find(params[:id])
    end

    def set_next_event_enabled
      @next_event_enabled = @inbox_state.next_event_enabled
    end

    def load_all_genres
      @all_genres = Genre.order(:name)
    end

    def load_all_presenters
      @all_presenters = Presenter.with_attached_logo.ordered_by_name.to_a
    end

    def build_editor_state_builder
      Backend::Events::EditorStateBuilder.new(
        inbox_state: @inbox_state,
        next_event_enabled: @next_event_enabled
      )
    end

    def editor_response
      @editor_response ||= Backend::Events::EditorResponse.new(
        controller: self,
        all_genres: @all_genres,
        all_presenters: @all_presenters,
        next_event_enabled: @next_event_enabled
      )
    end

    def selected_event_from(events)
      return prepare_new_event_state! if new_panel_requested?

      if params[:event_id].present?
        return Event.includes(
          :llm_enrichment,
          :import_event_images,
          :venue_record,
          promotion_banner_image_attachment: :blob,
          event_images: [ file_attachment: :blob ],
          event_presenters: { presenter: [ logo_attachment: :blob ] }
        ).find_by(id: params[:event_id])
      end

      events.first
    end

    def prepare_index_state!
      @editor_state_builder = build_editor_state_builder
      @filters = @inbox_state.filters
      @merge_run_filter_options = merge_run_filter_options
      @selected_merge_run_id = @editor_state_builder.selected_merge_run_id_for_status(@filters[:status])
      @events = @editor_state_builder.events_for_status(@filters[:status])
      @filtered_events_count = @editor_state_builder.filtered_events_count(@events)
      @status_filters = status_filters
    end

    def status_filters
      @status_filters ||= Event::STATUSES.reject { |status| status == "imported" }
    end

    def available_merge_runs
      ImportRun.where(source_type: "merge", status: "succeeded").order(finished_at: :desc, id: :desc).limit(5)
    end

    def merge_run_filter_options
      [ [ "Alle", "all" ] ] + @available_merge_runs.map do |run|
        [ helpers.merge_run_filter_option_label(run), run.id.to_s ]
      end
    end

    def event_params
      params.require(:event).permit(
        :title,
        :artist_name,
        :start_at,
        :doors_at,
        :venue_id,
        :venue_name,
        :venue,
        :city,
        :event_info,
        :support,
        :organizer_notes,
        :show_organizer_notes,
        :badge_text,
        :homepage_url,
        :instagram_url,
        :facebook_url,
        :youtube_url,
        :highlighted,
        :promotion_banner,
        :promotion_banner_kicker_text,
        :promotion_banner_cta_text,
        :promotion_banner_image_copyright,
        :promotion_banner_image_focus_x,
        :promotion_banner_image_focus_y,
        :promotion_banner_image_zoom,
        :published_at,
        :status,
        :editor_notes,
        presenter_ids: [],
        llm_enrichment_attributes: [
          :id,
          :venue,
          :genre_list,
          :event_description,
          :venue_description,
          :venue_external_url,
          :venue_address,
          :youtube_link,
          :instagram_link,
          :homepage_link,
          :facebook_link
        ]
      )
    end

    def event_attribute_params
      attributes = event_params.except(:presenter_ids)
      if attributes[:venue_name].blank? && attributes[:venue].present?
        attributes[:venue_name] = attributes[:venue]
      end

      attributes.except(:venue)
    end

    def editor_tab_for(event)
      return "event" if event.blank?

      params[:editor_tab].to_s.presence_in(allowed_editor_tabs_for(event)) || "event"
    end

    def new_editor_tab
      params[:editor_tab].to_s.presence_in(allowed_new_editor_tabs) || "event"
    end

    def new_editor_tab_param
      new_editor_tab == "event" ? nil : new_editor_tab
    end

    def editor_tab_for_success(target_event:)
      return "event" if target_event.blank? || target_event.id != @event.id

      editor_tab_for(@event)
    end

    def allowed_editor_tabs_for(event)
      tabs = %w[event event_image slider_images]
      tabs << "presenters"
      tabs << "llm_enrichment" if event.present? && event.persisted?
      tabs << "settings"
      tabs
    end

    def allowed_new_editor_tabs
      %w[event event_image slider_images presenters llm_enrichment settings]
    end

    def manual_ticket_url
      params.dig(:event, :ticket_url).to_s.strip.presence
    end

    def manual_ticket_sold_out
      ActiveModel::Type::Boolean.new.cast(params.dig(:event, :ticket_sold_out)) == true
    end

    def manual_ticket_fields_submitted?
      params[:event].respond_to?(:key?) && (params[:event].key?(:ticket_url) || params[:event].key?(:ticket_sold_out))
    end

    def validate_manual_ticket_url!(event)
      return if manual_ticket_url.blank?

      uri = URI.parse(manual_ticket_url)
      return if uri.is_a?(URI::HTTP) && uri.host.present?

      event.errors.add(:base, "Ticket-URL muss mit http:// oder https:// beginnen.")
    rescue URI::InvalidURIError
      event.errors.add(:base, "Ticket-URL ist ungültig.")
    end

    def llm_enrichment_run_source
      llm_importer_registry.resolve_run_source("llm_enrichment")
    end

    def new_panel_requested?
      ActiveModel::Type::Boolean.new.cast(params[:new])
    end

    def prepare_new_event_state!
      @event ||= Event.new(
        start_at: Time.current.change(hour: 20, min: 0),
        status: "needs_review",
        **manual_event_promoter_attributes
      )
      @selected_genre_ids ||= []
      @selected_presenter_ids ||= []
      @manual_image_form_values ||= {}
      @manual_ticket_url ||= nil
      @manual_ticket_sold_out = false if @manual_ticket_sold_out.nil?
      @active_editor_tab = new_editor_tab
      @event
    end

    def render_new_editor_frame
      render partial: "backend/events/editor_frame",
             locals: {
               event: @event,
               all_genres: @all_genres,
               all_presenters: @all_presenters,
               next_event_enabled: @next_event_enabled,
               filter_status: @inbox_state.current_status,
               active_editor_tab: @active_editor_tab,
               selected_genre_ids: @selected_genre_ids,
               selected_presenter_ids: @selected_presenter_ids,
               manual_ticket_url: @manual_ticket_url,
               manual_ticket_sold_out: @manual_ticket_sold_out,
               manual_image_form_values: @manual_image_form_values
             }
    end

    def llm_importer_registry
      @llm_importer_registry ||= Backend::ImportSources::ImporterRegistry.new
    end

    def llm_run_maintenance
      @llm_run_maintenance ||= Backend::ImportSources::RunMaintenance.new(registry: llm_importer_registry)
    end

    def llm_run_dispatcher
      @llm_run_dispatcher ||= Backend::ImportSources::RunDispatcher.new(registry: llm_importer_registry)
    end

    def llm_run_enqueuer
      @llm_run_enqueuer ||= Backend::ImportSources::RunEnqueuer.new(
        registry: llm_importer_registry,
        maintenance: llm_run_maintenance,
        dispatcher: llm_run_dispatcher
      )
    end

    def single_event_llm_enrichment_run_metadata(event)
      {
        "trigger_scope" => "single_event",
        "target_event_id" => event.id,
        "target_event_context" => single_event_llm_enrichment_context(event),
        "refresh_existing" => true,
        "triggered_at" => Time.current.iso8601
      }
    end

    def single_event_llm_enrichment_context(event)
      [
        event.artist_name.to_s.strip.presence,
        event.title.to_s.strip.presence,
        (event.start_at.present? ? I18n.l(event.start_at, format: "%d.%m.%Y %H:%M") : nil)
      ].compact.join(" · ")
    end

    def llm_enrichment_queue_notice(queue_position:)
      return "LLM-Enrichment für dieses Event wurde zur Warteschlange hinzugefügt." if queue_position.blank?

      "LLM-Enrichment für dieses Event wurde zur Warteschlange hinzugefügt (Position #{queue_position})."
    end

    def sync_venue_from_llm_fallback!(event)
      Venues::LlmFallbackAssignment.call(event: event, enrichment: event.llm_enrichment)
    end

    def respond_with_llm_enrichment_feedback(notice: nil, alert: nil)
      redirect_path = backend_events_path(
        status: event_editor_filter_status,
        event_id: @event.id,
        editor_tab: "llm_enrichment"
      )

      respond_to do |format|
        format.html do
          redirect_to redirect_path, notice:, alert:
        end

        format.turbo_stream do
          flash.now[:notice] = notice if notice.present?
          flash.now[:alert] = alert if alert.present?
          render turbo_stream: [
            turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
            turbo_stream.replace(
              "event_editor",
              partial: "backend/events/editor_frame",
              locals: {
                event: @event,
                all_genres: @all_genres,
                all_presenters: @all_presenters,
                next_event_enabled: @next_event_enabled,
                filter_status: event_editor_filter_status,
                active_editor_tab: "llm_enrichment"
              }
            )
          ]
        end
      end
    end

    def event_editor_filter_status
      @inbox_state.navigation_status || params[:status].to_s.presence_in(status_filters) || @event.status
    end

    def genre_ids_from_params
      Array(params.dig(:event, :genre_ids)).reject(&:blank?).map(&:to_i)
    end

    def manual_event_promoter_id
      MANUAL_EVENT_PROMOTER_ID
    end

    def manual_event_promoter_name
      MANUAL_EVENT_PROMOTER_NAME
    end

    def manual_event_promoter_attributes
      {
        promoter_id: manual_event_promoter_id,
        promoter_name: manual_event_promoter_name
      }
    end

    def presenter_ids_from_params
      Array(params.dig(:event, :presenter_ids)).reject(&:blank?).map(&:to_i).uniq
    end

    def manual_image_params
      params.fetch(:event_image, ActionController::Parameters.new).permit(
        :sub_text,
        :grid_variant,
        :card_focus_x,
        :card_focus_y,
        :card_zoom,
        :detail_hero_sub_text,
        :slider_alt_text,
        :slider_sub_text,
        detail_hero_signed_ids: [],
        slider_signed_ids: [],
        detail_hero_files: [],
        slider_files: []
      )
    end

    def promotion_banner_image_params
      params.fetch(:event_promotion_banner_image, ActionController::Parameters.new).permit(
        :promotion_banner_image_signed_id,
        :remove_promotion_banner_image
      )
    end

    def manual_image_form_values
      permitted = manual_image_params.to_h.deep_symbolize_keys

      {
        sub_text: permitted[:sub_text].presence || permitted[:detail_hero_sub_text],
        grid_variant: permitted[:grid_variant],
        card_focus_x: permitted[:card_focus_x],
        card_focus_y: permitted[:card_focus_y],
        card_zoom: permitted[:card_zoom],
        slider_alt_text: permitted[:slider_alt_text],
        slider_sub_text: permitted[:slider_sub_text],
        detail_hero_signed_ids: Array(permitted[:detail_hero_signed_ids]).reject(&:blank?),
        slider_signed_ids: Array(permitted[:slider_signed_ids]).reject(&:blank?)
      }
    end

    def assign_genres!(event)
      return unless params[:event].is_a?(ActionController::Parameters) || params[:event].is_a?(Hash)

      ids = genre_ids_from_params
      event.genres = Genre.where(id: ids)
    end

    def sync_presenters!(event)
      return unless params[:event].respond_to?(:key?) && params[:event].key?(:presenter_ids)

      valid_presenter_ids = Presenter.where(id: presenter_ids_from_params).pluck(:id)

      event.event_presenters.destroy_all

      presenter_ids_from_params.each_with_index do |presenter_id, index|
        next unless valid_presenter_ids.include?(presenter_id)

        event.event_presenters.create!(presenter_id:, position: index + 1)
      end
    end

    def refresh_completeness!(event)
      result = Editorial::EventCompletenessChecker.new(event: event).call
      event.update!(
        completeness_score: result.score,
        completeness_flags: result.flags,
        status: normalized_status_for(event, result)
      )
    end

    def normalized_status_for(event, completeness_result)
      return event.status if event.published? || event.status == "rejected"

      completeness_result.ready_for_publish? ? "ready_for_publish" : "needs_review"
    end

    def set_publishing_fields!(event)
      event.sync_publication_fields(user: current_user)
    end

    def attach_manual_event_images!
      created_images = []
      hero_signed_ids = signed_ids_from(manual_image_params[:detail_hero_signed_ids], label: "Eventbild")
      slider_signed_ids = signed_ids_from(manual_image_params[:slider_signed_ids], label: "Slider-Bilder")
      hero_files = uploaded_files_from(manual_image_params[:detail_hero_files], label: "Eventbild")
      slider_files = uploaded_files_from(manual_image_params[:slider_files], label: "Slider-Bilder")

      hero_sources = hero_signed_ids.presence || hero_files
      slider_sources = slider_signed_ids.presence || slider_files

      if hero_sources.size > 1
        raise ArgumentError, "Für das Eventbild ist nur eine Datei erlaubt."
      end

      hero_sources.each do |upload_source|
        image = @event.event_images.new(
          purpose: EventImage::PURPOSE_DETAIL_HERO,
          sub_text: manual_detail_hero_sub_text,
          grid_variant: manual_image_params[:grid_variant],
          card_focus_x: manual_image_params[:card_focus_x],
          card_focus_y: manual_image_params[:card_focus_y],
          card_zoom: manual_image_params[:card_zoom]
        )
        image.file.attach(upload_source)
        image.save!
        created_images << image
      end

      slider_sources.each do |upload_source|
        image = @event.event_images.new(
          purpose: EventImage::PURPOSE_SLIDER,
          alt_text: manual_image_params[:slider_alt_text],
          sub_text: manual_image_params[:slider_sub_text]
        )
        image.file.attach(upload_source)
        image.save!
        created_images << image
      end

      created_images
    end

    def detail_hero_crop_params
      params.fetch(:event_image, ActionController::Parameters.new).permit(
        :sub_text,
        :grid_variant,
        :card_focus_x,
        :card_focus_y,
        :card_zoom
      )
    end

    def update_detail_hero_crop!
      return unless params[:event_image].respond_to?(:key?)

      detail_hero = @event.event_images.detail_hero.ordered.first
      return unless detail_hero.present?

      detail_hero.update!(detail_hero_crop_params)
    end

    def prepare_promotion_banner_image(event)
      image_params = promotion_banner_image_params

      event.pending_promotion_banner_image_blob = resolve_promotion_banner_signed_blob(
        image_params[:promotion_banner_image_signed_id],
        event: event
      )
      event.remove_promotion_banner_image = ActiveModel::Type::Boolean.new.cast(image_params[:remove_promotion_banner_image])
    end

    def persist_promotion_banner_image!(event)
      if event.pending_promotion_banner_image_blob.present?
        event.promotion_banner_image.attach(event.pending_promotion_banner_image_blob)
      elsif event.remove_promotion_banner_image? && event.promotion_banner_image.attached?
        event.promotion_banner_image.purge_later
      end
    end

    def resolve_promotion_banner_signed_blob(signed_id, event:)
      return if signed_id.blank?

      ActiveStorage::Blob.find_signed!(signed_id)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      event.errors.add(:base, "Promotion-Banner-Bild: Der temporäre Upload ist ungültig oder abgelaufen.")
      nil
    end

    def slider_image_update_params
      raw_updates = params.fetch(:event_image_updates, ActionController::Parameters.new)
      raw_updates.to_unsafe_h.each_with_object({}) do |(id, attributes), permitted|
        next unless id.to_s.match?(/\A\d+\z/)
        next unless attributes.respond_to?(:to_h)

        normalized = ActionController::Parameters.new(attributes).permit(:alt_text, :sub_text).to_h
        permitted[id.to_i] = normalized
      end
    end

    def update_slider_image_metadata!
      updates = slider_image_update_params
      return if updates.empty?

      slider_images = @event.event_images.slider.where(id: updates.keys).index_by(&:id)

      updates.each do |image_id, attributes|
        image = slider_images[image_id]
        next if image.blank?

        image.update!(attributes)
      end
    end

    def create_manual_ticket_offer!(event)
      return unless should_persist_manual_ticket_offer?

      event.event_offers.create!(
        source: "manual",
        source_event_id: event.id.to_s,
        ticket_url: manual_ticket_url,
        priority_rank: 0,
        sold_out: manual_ticket_sold_out
      )
    end

    def sync_ticket_offer!(event)
      return unless manual_ticket_fields_submitted?

      offer = event.manual_ticket_offer

      if should_persist_manual_ticket_offer?
        offer ||= event.event_offers.build(
          source: "manual",
          source_event_id: event.id.to_s,
          priority_rank: 0
        )
        offer.ticket_url = manual_ticket_url
        offer.sold_out = manual_ticket_sold_out
        offer.save!
      elsif offer.present?
        offer.destroy!
      end
    end

    def should_persist_manual_ticket_offer?
      manual_ticket_url.present? || manual_ticket_sold_out
    end

    def uploaded_files_from(values, label:)
      raw_values = Array(values)
      valid_files = raw_values.filter_map do |value|
        next if value.blank?
        next persist_uploaded_blob(value) if value.respond_to?(:original_filename) && value.respond_to?(:content_type)

        nil
      end

      return valid_files if raw_values.reject(&:blank?).size == valid_files.size

      raise ArgumentError, "#{label}: Bitte gültige Bilddateien auswählen."
    end

    def signed_ids_from(values, label:)
      Array(values).filter_map do |signed_id|
        next if signed_id.blank?
        next ActiveStorage::Blob.find_signed!(signed_id)

        raise ArgumentError, "#{label}: Der temporäre Upload ist ungültig oder abgelaufen."
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
        raise ArgumentError, "#{label}: Der temporäre Upload ist ungültig oder abgelaufen."
      end
    end

    def manual_detail_hero_sub_text
      manual_image_params[:sub_text].presence || manual_image_params[:detail_hero_sub_text]
    end

    def persist_uploaded_blob(upload)
      io = upload.respond_to?(:tempfile) ? upload.tempfile : upload
      io.rewind if io.respond_to?(:rewind)

      ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: upload.original_filename,
        content_type: upload.content_type
      )
    end

    def save_and_publish_requested?
      ActiveModel::Type::Boolean.new.cast(params[:save_and_publish])
    end

    def update_success_message(previous_venue_id:)
      return venue_success_message if venue_saved?(previous_venue_id:)

      save_and_publish_requested? ? "Event wurde gespeichert und publiziert." : "Event wurde gespeichert."
    end

    def venue_saved?(previous_venue_id:)
      @event.venue_id.present? && previous_venue_id != @event.venue_id
    end

    def venue_success_message
      save_and_publish_requested? ? "Venue wurde gespeichert und Event publiziert." : "Venue wurde gespeichert."
    end
  end
end
