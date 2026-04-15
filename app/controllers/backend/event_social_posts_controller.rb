module Backend
  class EventSocialPostsController < BaseController
    before_action :set_event
    before_action :set_event_social_post, only: [ :update, :publish, :regenerate ]

    def create
      social_post = draft_sync.call(event: @event, platform: platform_param)
      redirect_to redirect_path, notice: "#{platform_label(social_post)}-Draft wurde erzeugt."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to redirect_path, alert: error.record.errors.full_messages.to_sentence
    rescue Meta::Error => error
      redirect_to redirect_path, alert: error.message
    end

    def quick_publish
      social_post = @event.social_post_for(platform_param)

      if social_post&.published?
        redirect_to redirect_path, notice: "#{platform_label(social_post)}-Post ist bereits veröffentlicht."
        return
      end

      if social_post&.publishing?
        redirect_to redirect_path, notice: "#{platform_label(social_post)}-Post wird bereits im Hintergrund veröffentlicht."
        return
      end

      social_post ||= draft_sync.call(event: @event, platform: platform_param)
      enqueue_publish!(social_post)

      redirect_to redirect_path, notice: "#{platform_label(social_post)}-Post wird im Hintergrund veröffentlicht."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to redirect_path, alert: error.record.errors.full_messages.to_sentence
    rescue ActiveJob::EnqueueError => error
      social_post&.mark_failed!(error.message)
      redirect_to redirect_path, alert: error.message
    rescue Meta::Error => error
      redirect_to redirect_path, alert: error.message
    end

    def update
      unless @event_social_post.caption_editable?
        redirect_to redirect_path, alert: "#{platform_label(@event_social_post)}-Post kann in diesem Status nicht bearbeitet werden."
        return
      end

      previous_card_artist_name = @event_social_post.card_artist_name
      previous_card_meta_line = @event_social_post.card_meta_line
      @event_social_post.assign_attributes(event_social_post_params)
      card_text_changed = previous_card_artist_name != @event_social_post.card_artist_name ||
        previous_card_meta_line != @event_social_post.card_meta_line
      @event_social_post.reset_workflow_to_draft! if (@event_social_post.will_save_change_to_caption? || card_text_changed) && !@event_social_post.draft?
      @event_social_post.save!
      draft_sync.refresh_rendered_assets!(@event_social_post) if card_text_changed

      redirect_to redirect_path, notice: "#{platform_label(@event_social_post)}-Social-Draft wurde gespeichert."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to redirect_path, alert: error.record.errors.full_messages.to_sentence
    end

    def publish
      if @event_social_post.published?
        redirect_to redirect_path, notice: "#{platform_label(@event_social_post)}-Post ist bereits veröffentlicht."
        return
      end

      if @event_social_post.publishing?
        redirect_to redirect_path, notice: "#{platform_label(@event_social_post)}-Post wird bereits im Hintergrund veröffentlicht."
        return
      end

      enqueue_publish!(@event_social_post)
      redirect_to redirect_path, notice: "#{platform_label(@event_social_post)}-Post wird im Hintergrund veröffentlicht."
    rescue ActiveJob::EnqueueError => error
      @event_social_post.mark_failed!(error.message)
      redirect_to redirect_path, alert: error.message
    rescue Meta::Error => error
      redirect_to redirect_path, alert: error.message
    end

    def regenerate
      social_post = draft_sync.call(event: @event, platform: @event_social_post.platform)
      redirect_to redirect_path, notice: "#{platform_label(social_post)}-Draft wurde neu erzeugt."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to redirect_path, alert: error.record.errors.full_messages.to_sentence
    rescue Meta::Error => error
      redirect_to redirect_path, alert: error.message
    end

    private

    def set_event
      @event = Event.find(params[:event_id])
    end

    def set_event_social_post
      @event_social_post = @event.event_social_posts.find(params[:id])
    end

    def event_social_post_params
      params.require(:event_social_post).permit(:caption, :card_artist_name, :card_meta_line)
    end

    def platform_param
      params[:platform].to_s
    end

    def draft_sync
      @draft_sync ||= Meta::EventSocialPostDraftSync.new
    end

    def enqueue_publish!(social_post)
      social_post.ensure_publishable!
      meta_access_status.ensure_publishable!(force: true)
      social_post.mark_publishing!
      Meta::PublishEventSocialPostJob.perform_later(social_post.id, current_user.id)
    end

    def redirect_path
      backend_events_path(
        status: params[:inbox_status].presence || @event.status,
        event_id: @event.id,
        editor_tab: "social"
      )
    end

    def platform_label(social_post)
      view_context.event_social_post_platform_label(social_post.platform)
    end

    def meta_access_status
      @meta_access_status ||= Meta::AccessStatus.new
    end
  end
end
