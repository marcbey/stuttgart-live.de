module Backend
  class EventImagesController < BaseController
    before_action :set_event
    before_action :set_event_image, only: [ :update, :destroy ]

    def create
      purpose = create_params[:purpose].to_s
      files = uploaded_files

      if files.blank?
        redirect_to editor_redirect_path, alert: "Bitte gültige Bilddateien auswählen."
        return
      end

      if purpose != EventImage::PURPOSE_SLIDER && files.size > 1
        redirect_to editor_redirect_path, alert: "Für diesen Bildtyp ist nur eine Datei pro Upload erlaubt."
        return
      end

      created = 0
      errors = []

      EventImage.transaction do
        replace_unique_images!(purpose: purpose, grid_variant: create_params[:grid_variant])

        files.each do |uploaded_file|
          image = @event.event_images.new(
            purpose: purpose,
            grid_variant: create_params[:grid_variant],
            hero_focus_position: create_params[:hero_focus_position],
            alt_text: create_params[:alt_text],
            sub_text: create_params[:sub_text],
            card_focus_x: create_params[:card_focus_x],
            card_focus_y: create_params[:card_focus_y],
            card_zoom: create_params[:card_zoom]
          )
          image.file.attach(uploaded_file)

          if image.save
            created += 1
          else
            errors << image.errors.full_messages.to_sentence
          end
        end

        raise ActiveRecord::Rollback if errors.any?
      end

      if errors.any?
        redirect_to editor_redirect_path, alert: errors.uniq.join(" | ")
      else
        notice =
          if created == 1
            "Bild wurde hochgeladen."
          else
            "#{created} Bilder wurden hochgeladen."
          end
        redirect_to editor_redirect_path, notice: notice
      end
    end

    def update
      if @event_image.update(update_params)
        respond_to do |format|
          format.turbo_stream do
            flash.now[:notice] = event_image_update_notice
            render_event_image_update_turbo_stream
          end
          format.html { redirect_to editor_redirect_path, notice: event_image_update_notice }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            flash.now[:alert] = @event_image.errors.full_messages.to_sentence
            render turbo_stream: turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
                   status: :unprocessable_entity
          end
          format.html { redirect_to editor_redirect_path, alert: @event_image.errors.full_messages.to_sentence }
        end
      end
    end

    def create_from_import
      import_image = @event.import_event_images.find(import_image_params[:import_event_image_id])
      purpose = import_image_params[:purpose].to_s
      grid_variant = import_image_params[:grid_variant]

      EventImage.transaction do
        replace_unique_images!(purpose: purpose, grid_variant: grid_variant)

        Backend::ImportEventImageImporter.call(
          event: @event,
          import_event_image: import_image,
          purpose: purpose,
          grid_variant: grid_variant
        )
      end

      redirect_to editor_redirect_path, notice: "Import-Bild wurde in die Redaktion übernommen."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to editor_redirect_path, alert: e.record.errors.full_messages.to_sentence
    rescue StandardError => e
      redirect_to editor_redirect_path, alert: e.message
    end

    def destroy
      @event_image.destroy!

      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = "Bild wurde gelöscht."
          render_slider_image_destroy_turbo_stream
        end
        format.html { redirect_to editor_redirect_path, notice: "Bild wurde gelöscht." }
      end
    end

    def destroy_editorial_main
      @event.event_images.detail_hero.find_each(&:destroy!)

      respond_to do |format|
        format.turbo_stream do
          flash.now[:notice] = "Eventbild wurde gelöscht."
          render_event_image_section_turbo_stream
        end
        format.html { redirect_to editor_redirect_path, notice: "Eventbild wurde gelöscht." }
      end
    end

    private

    def set_event
      @event = Event.find(params[:event_id])
    end

    def set_event_image
      @event_image = @event.event_images.find(params[:id])
    end

    def create_params
      params.require(:event_image).permit(
        :purpose,
        :grid_variant,
        :hero_focus_position,
        :alt_text,
        :sub_text,
        :card_focus_x,
        :card_focus_y,
        :card_zoom,
        files: []
      )
    end

    def update_params
      params.require(:event_image).permit(:alt_text, :sub_text, :grid_variant, :hero_focus_position, :card_focus_x, :card_focus_y, :card_zoom)
    end

    def import_image_params
      params.require(:event_image).permit(:import_event_image_id, :purpose, :grid_variant)
    end

    def replace_unique_images!(purpose:, grid_variant: nil)
      case purpose.to_s
      when EventImage::PURPOSE_DETAIL_HERO
        @event.event_images.detail_hero.find_each(&:destroy!)
      end
    end

    def uploaded_files
      Array(create_params[:files]).filter_map do |value|
        next if value.blank?
        next value if value.respond_to?(:original_filename) && value.respond_to?(:content_type)

        nil
      end
    end

    def editor_redirect_path
      status = params[:status].to_s
      status = @event.status if status.blank?
      backend_events_path(status: status, event_id: @event.id)
    end

    def render_event_image_update_turbo_stream
      if @event_image.slider?
        render turbo_stream: [
          turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
          turbo_stream.replace(
            view_context.dom_id(@event_image, :slider_card),
            partial: "backend/events/slider_image_editor_card",
            locals: { event: @event, image: @event_image, editor_status: current_editor_status }
          )
        ]
        return
      end

      render_event_image_section_turbo_stream
    end

    def render_slider_image_destroy_turbo_stream
      unless @event_image.slider?
        render turbo_stream: turbo_stream.update("flash-messages", partial: "layouts/flash_messages")
        return
      end

      render turbo_stream: [
        turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
        turbo_stream.remove(view_context.dom_id(@event_image, :slider_card))
      ]
    end

    def render_event_image_section_turbo_stream
      render turbo_stream: [
        turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
        turbo_stream.replace(
          view_context.dom_id(@event, :event_image_section),
          partial: "backend/events/event_image_section",
          locals: { event: @event, editor_status: current_editor_status }
        )
      ]
    end

    def current_editor_status
      params[:status].presence || @event.status
    end

    def event_image_update_notice
      @event_image.detail_hero? ? "Eventbild wurde gespeichert." : "Bild-Metadaten wurden gespeichert."
    end
  end
end
