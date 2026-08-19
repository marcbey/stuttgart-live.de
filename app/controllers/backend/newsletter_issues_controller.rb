module Backend
  class NewsletterIssuesController < BaseController
    AVAILABLE_EVENTS_LIMIT = 100

    before_action :set_issue, only: %i[
      show edit update destroy sync_mailjet send_test send_test_list send_now sort_by_date populate_from_interest
    ]
    before_action :set_collections, only: %i[index show edit new create update]

    def index
      @issues = NewsletterIssue.ordered_for_backend
      @issue = selected_issue || NewsletterIssue.new
    end

    def show
    end

    def new
      @issue = NewsletterIssue.new
    end

    def create
      @issue = NewsletterIssue.new(issue_params)
      @issue.created_by = current_user

      if @issue.save
        redirect_to backend_newsletter_path(@issue), notice: "Newsletter wurde angelegt."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def create_weekly_genre_mix
      issue = Newsletter::CreateWeeklyGenreMixIssue.call(user: current_user)

      redirect_to backend_newsletter_path(issue),
                  notice: "Wochenmix-Draft wurde mit #{issue.newsletter_issue_items.count} Events erstellt."
    end

    def edit
    end

    def update
      if @issue.update(issue_params)
        @issue.sort_weekly_mix_positions!
        redirect_to backend_newsletter_path(@issue), notice: "Newsletter wurde gespeichert."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @issue.destroy!
      redirect_to backend_newsletters_path, notice: "Newsletter wurde gelöscht."
    end

    def sync_mailjet
      if Newsletter::SyncIssueToMailjet.call(@issue)
        redirect_to backend_newsletter_path(@issue), notice: "Mailjet-Draft wurde aktualisiert."
      else
        redirect_to backend_newsletter_path(@issue), alert: @issue.mailjet_error_message
      end
    end

    def send_test
      if Newsletter::SendIssueTest.call(@issue)
        redirect_to backend_newsletter_path(@issue), notice: "Testmail wurde an #{Newsletter::MailjetClient::TEST_EMAILS.to_sentence} gesendet."
      else
        redirect_to backend_newsletter_path(@issue), alert: @issue.mailjet_error_message
      end
    end

    def send_test_list
      if Newsletter::SendIssueTestList.call(@issue, user: current_user)
        redirect_to backend_newsletter_path(@issue), notice: "Newsletter wurde an die konfigurierte Mailjet-Testliste gesendet."
      else
        redirect_to backend_newsletter_path(@issue), alert: @issue.mailjet_error_message
      end
    end

    def send_now
      if Newsletter::SendIssue.call(@issue, user: current_user)
        redirect_to backend_newsletter_path(@issue), notice: "Newsletter wurde versendet."
      else
        redirect_to backend_newsletter_path(@issue), alert: @issue.mailjet_error_message
      end
    end

    def sort_by_date
      @issue.sort_items_by_date!
      redirect_to backend_newsletter_path(@issue), notice: "Inhalte wurden nach Datum sortiert."
    end

    def populate_from_interest
      added_count = Newsletter::PopulateIssueFromInterest.call(@issue)
      redirect_to backend_newsletter_path(@issue), notice: "#{added_count} passende Events wurden hinzugefügt."
    end

    private

    def set_issue
      @issue = NewsletterIssue.includes(newsletter_issue_items: :item).find(params[:id])
    end

    def set_collections
      @issues = NewsletterIssue.ordered_for_backend
      @newsletter_interests = NewsletterInterest.publicly_selectable
      @available_events = available_events_for_newsletter
      @available_blog_posts = BlogPost.published_live.limit(100)
    end

    def available_events_for_newsletter
      highlighted_events = newsletter_event_relation.homepage_highlights.limit(AVAILABLE_EVENTS_LIMIT).to_a
      remaining_limit = AVAILABLE_EVENTS_LIMIT - highlighted_events.length
      return highlighted_events unless remaining_limit.positive?

      other_events = newsletter_event_relation.where.not(id: highlighted_events.map(&:id)).limit(remaining_limit).to_a
      highlighted_events + other_events
    end

    def newsletter_event_relation
      Event.published_live.includes(
        :venue_record,
        :import_event_images,
        promotion_banner_image_attachment: :blob,
        event_images: [ file_attachment: :blob ]
      )
    end

    def selected_issue
      selected_id = params[:newsletter_id].presence || params[:id].presence
      return if selected_id.blank?

      @issues.find { |issue| issue.id == selected_id.to_i }
    end

    def issue_params
      params.require(:newsletter_issue).permit(
        :title,
        :subject,
        :jump_menu_title,
        :intro,
        :team_tip_profile_key,
        :team_tip_name,
        :team_tip_role,
        :team_tip_image_url,
        :team_tip_text,
        newsletter_issue_items_attributes: [
          :id,
          :position,
          :headline_override,
          :teaser_override,
          :cta_label,
          :section_key,
          :_destroy
        ]
      )
    end
  end
end
