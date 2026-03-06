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
            alt_text: create_params[:alt_text],
            sub_text: create_params[:sub_text]
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
        redirect_to editor_redirect_path, notice: "Bild-Metadaten wurden gespeichert."
      else
        redirect_to editor_redirect_path, alert: @event_image.errors.full_messages.to_sentence
      end
    end

    def destroy
      @event_image.destroy!
      redirect_to editor_redirect_path, notice: "Bild wurde gelöscht."
    end

    private

    def set_event
      @event = Event.find(params[:event_id])
    end

    def set_event_image
      @event_image = @event.event_images.find(params[:id])
    end

    def create_params
      params.require(:event_image).permit(:purpose, :grid_variant, :alt_text, :sub_text, files: [])
    end

    def update_params
      params.require(:event_image).permit(:alt_text, :sub_text, :card_focus_x, :card_focus_y, :card_zoom)
    end

    def replace_unique_images!(purpose:, grid_variant:)
      case purpose.to_s
      when EventImage::PURPOSE_DETAIL_HERO
        @event.event_images.detail_hero.find_each(&:destroy!)
      when EventImage::PURPOSE_GRID_TILE
        variant = grid_variant.to_s.strip
        return if variant.blank?

        @event.event_images.grid_tile.where(grid_variant: variant).find_each(&:destroy!)
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
  end
end
