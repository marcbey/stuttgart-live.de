module Public
  class NewsletterSubscribersController < ApplicationController
    allow_unauthenticated_access only: [ :new, :create ]
    layout "newsletter", only: :new
    before_action -> { response.headers["Cache-Control"] = "no-store" }
    rate_limit to: 10, within: 3.minutes, only: :create,
               with: -> { redirect_to new_newsletter_subscriber_path, alert: "Bitte versuchen Sie es später erneut." }

    def new
      @subscriber = NewsletterSubscriber.new
    end

    def create
      if params[:signup_step] == "details"
        @subscriber = NewsletterSubscriber.new(newsletter_subscriber_params)
        return render :new, layout: "newsletter"
      end

      subscriber = existing_or_new_subscriber
      if subscriber.request_signup(newsletter_subscriber_params.merge(source: newsletter_signup[:source]))
        respond_to_success(subscriber)
      else
        respond_to_error(subscriber)
      end
    end

    private

    def newsletter_subscriber_params
      params.require(:newsletter_subscriber).permit(:email, :newsletter_consent, :tracking_consent, newsletter_interest_ids: [])
    end

    def existing_or_new_subscriber
      existing = NewsletterSubscriber.find_by_normalized_email(newsletter_subscriber_params[:email])
      return existing if existing&.pending_confirmation?

      NewsletterSubscriber.new(newsletter_subscriber_params.merge(source: newsletter_signup[:source]))
    end

    def newsletter_signup
      @newsletter_signup ||= helpers.newsletter_signup_config(
        params[:context],
        return_to: params[:return_to].presence,
        source: params[:source].presence
      )
    end

    def newsletter_redirect_target
      newsletter_signup[:return_to]
    end

    def newsletter_frame_request?
      turbo_frame_request? && request.headers["Turbo-Frame"] == newsletter_signup[:frame_id]
    end

    def respond_to_success(subscriber)
      if newsletter_frame_request?
        render_signup(subscriber:, confirmation_pending: subscriber.pending_confirmation?, status: :ok)
      else
        redirect_to newsletter_redirect_target,
                    notice: "Danke! Bitte bestätige jetzt deine E-Mail-Adresse."
      end
    end

    def respond_to_error(subscriber)
      if newsletter_frame_request?
        render_signup(subscriber:, confirmation_pending: false, status: :unprocessable_entity)
      else
        @subscriber = subscriber
        render :new, layout: "newsletter", status: :unprocessable_entity
      end
    end

    def render_signup(subscriber:, confirmation_pending:, status:)
      render partial: "public/newsletter_subscribers/signup",
             locals: { subscriber:, signup: newsletter_signup, subscribed: confirmation_pending },
             status:
    end
  end
end
