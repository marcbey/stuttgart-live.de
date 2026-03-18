module Backend
  class EventsController < BaseController
    before_action :set_event, only: [ :show, :update, :publish, :unpublish ]
    before_action :set_inbox_state
    before_action :set_next_event_enabled, only: [ :index, :show, :update, :publish, :unpublish ]
    before_action :load_all_genres, only: [ :index, :show, :new, :create, :update, :unpublish ]

    def index
      @latest_successful_merge_run = latest_successful_merge_run
      @editor_state_builder = build_editor_state_builder
      @filters = @inbox_state.filters
      @selected_merge_run_id = @editor_state_builder.selected_merge_run_id_for_status(@filters[:status])
      @events = @editor_state_builder.events_for_status(@filters[:status])
      @filtered_events_count = @editor_state_builder.filtered_events_count(@events)
      @status_filters = status_filters
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
    end

    def new
      @event = Event.new(start_at: Time.current.change(hour: 20, min: 0), status: "needs_review")
      @selected_genre_ids = []
      @manual_image_form_values = {}
      @manual_ticket_url = nil
    end

    def create
      @event = Event.new(event_params)
      @selected_genre_ids = genre_ids_from_params
      @manual_image_form_values = manual_image_form_values
      @manual_ticket_url = manual_ticket_url
      created_images = []
      creation_alert = nil

      set_publishing_fields!(@event)

      Event.transaction do
        unless @event.save
          creation_alert = "Event konnte nicht erstellt werden."
          raise ActiveRecord::Rollback
        end

        assign_genres!(@event)
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
          @event = Event.new(event_params)
          created_successfully = false
        end
      end

      if !created_successfully
        flash.now[:alert] = creation_alert || "Event konnte nicht erstellt werden."
        render :new, status: :unprocessable_entity
      else
        redirect_to backend_events_path(status: @event.status, event_id: @event.id), notice: "Event wurde erstellt."
      end
    end

    def update
      @next_event_enabled = @inbox_state.persist_next_event_preference!(params[:next_event_enabled]) if params.key?(:next_event_enabled)
      navigation_status = @inbox_state.navigation_status

      @event.assign_attributes(event_params)
      @event.status = "published" if save_and_publish_requested?
      set_publishing_fields!(@event)

      if @event.save
        begin
          update_detail_hero_crop!
        rescue ActiveRecord::RecordInvalid => e
          @event.errors.add(:base, e.record.errors.full_messages.to_sentence)
          editor_response.validation_error(event: @event, filter_status: navigation_status || @event.status)
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

        editor_response.success(
          editor_state: build_editor_state_builder.build(preferred_event: @event, navigation_status: navigation_status),
          notice: update_success_message
        )
      else
        editor_response.validation_error(event: @event, filter_status: navigation_status || @event.status)
      end
    end

    def publish
      @event.publish_now!(user: current_user, auto_published: false)
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
        notice: "Event wurde depublisht."
      )
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
        status_filters: status_filters
      )
    end

    def set_event
      @event = Event.includes(:import_event_images, event_images: [ file_attachment: :blob ]).find(params[:id])
    end

    def set_next_event_enabled
      @next_event_enabled = @inbox_state.next_event_enabled
    end

    def load_all_genres
      @all_genres = Genre.order(:name)
    end

    def build_editor_state_builder
      Backend::Events::EditorStateBuilder.new(
        inbox_state: @inbox_state,
        latest_successful_merge_run: @latest_successful_merge_run || latest_successful_merge_run,
        next_event_enabled: @next_event_enabled
      )
    end

    def editor_response
      @editor_response ||= Backend::Events::EditorResponse.new(
        controller: self,
        all_genres: @all_genres,
        next_event_enabled: @next_event_enabled
      )
    end

    def selected_event_from(events)
      if params[:event_id].present?
        return Event.includes(:import_event_images, event_images: [ file_attachment: :blob ]).find_by(id: params[:event_id])
      end

      events.first
    end

    def status_filters
      @status_filters ||= Event::STATUSES.reject { |status| status == "imported" }
    end

    def latest_successful_merge_run
      ImportRun.where(source_type: "merge", status: "succeeded").order(finished_at: :desc, id: :desc).first
    end

    def event_params
      params.require(:event).permit(
        :title,
        :artist_name,
        :start_at,
        :doors_at,
        :venue,
        :city,
        :event_info,
        :organizer_notes,
        :show_organizer_notes,
        :badge_text,
        :homepage_url,
        :instagram_url,
        :facebook_url,
        :youtube_url,
        :promoter_id,
        :highlighted,
        :status,
        :editor_notes
      )
    end

    def manual_ticket_url
      params.dig(:event, :ticket_url).to_s.strip.presence
    end

    def genre_ids_from_params
      Array(params.dig(:event, :genre_ids)).reject(&:blank?).map(&:to_i)
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

    def create_manual_ticket_offer!(event)
      return if manual_ticket_url.blank?

      event.event_offers.create!(
        source: "manual",
        source_event_id: event.id.to_s,
        ticket_url: manual_ticket_url,
        priority_rank: 0,
        sold_out: false
      )
    end

    def sync_ticket_offer!(event)
      preferred_offer = event.preferred_ticket_offer

      if manual_ticket_url.present?
        offer = preferred_offer || event.event_offers.build(
          source: "manual",
          source_event_id: event.id.to_s,
          priority_rank: 0,
          sold_out: false
        )
        offer.ticket_url = manual_ticket_url
        offer.save!
      elsif preferred_offer.present?
        preferred_offer.update!(ticket_url: nil)
      end
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

    def update_success_message
      save_and_publish_requested? ? "Event wurde gespeichert und publiziert." : "Event wurde gespeichert."
    end
  end
end
