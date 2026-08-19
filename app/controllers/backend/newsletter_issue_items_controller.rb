module Backend
  class NewsletterIssueItemsController < BaseController
    before_action :set_issue

    def create
      item = newsletter_item
      section_key = section_key_for(item)
      if missing_weekly_mix_section_key?(item, section_key)
        redirect_to backend_newsletter_path(@issue), alert: "Bitte ein Genre auswählen."
        return
      end

      @issue.newsletter_issue_items.create!(
        item:,
        position: next_position,
        section_key:,
        cta_label: item.is_a?(Event) ? "Zum Event" : "Zur News"
      )
      @issue.sort_weekly_mix_positions!
      redirect_to backend_newsletter_path(@issue), notice: "Inhalt wurde hinzugefügt."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to backend_newsletter_path(@issue), alert: error.record.errors.full_messages.to_sentence
    end

    def destroy
      @issue.newsletter_issue_items.find(params[:id]).destroy!
      redirect_to backend_newsletter_path(@issue), notice: "Inhalt wurde entfernt."
    end

    private

    def set_issue
      @issue = NewsletterIssue.find(params[:newsletter_id])
    end

    def newsletter_item
      case params[:item_type].to_s
      when "Event"
        Event.published_live.find(params[:item_id])
      when "BlogPost"
        BlogPost.published_live.find(params[:item_id])
      else
        raise ActiveRecord::RecordInvalid, @issue.newsletter_issue_items.build
      end
    end

    def next_position
      @issue.newsletter_issue_items.maximum(:position).to_i + 1
    end

    def section_key_for(item)
      return if item.is_a?(BlogPost)
      return selected_section_key if @issue.genre_weekly_mix?

      selected_section_key.presence || inferred_section_key_for(item)
    end

    def missing_weekly_mix_section_key?(item, section_key)
      @issue.genre_weekly_mix? && item.is_a?(Event) && section_key.blank?
    end

    def selected_section_key
      key = params[:section_key].to_s.strip
      Newsletter::HeaderGenreGroups.all.any? { |group| group.slug == key } ? key : nil
    end

    def inferred_section_key_for(item)
      event_genre_slugs = item.genres.map(&:slug)
      Newsletter::HeaderGenreGroups.all.find { |group| event_genre_slugs.include?(group.slug) }&.slug
    end
  end
end
