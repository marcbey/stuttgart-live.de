module Public
  class NewsletterSubscribersController < ApplicationController
    allow_unauthenticated_access only: [ :create ]

    def create
      subscriber = NewsletterSubscriber.new(newsletter_subscriber_params.merge(source: newsletter_signup[:source]))

      if subscriber.save
        respond_to_success(subscriber)
      else
        respond_to_error(subscriber)
      end
    end

    private

    def newsletter_subscriber_params
      params.require(:newsletter_subscriber).permit(:email)
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
        render_signup(subscriber:, subscribed: true, status: :ok)
      else
        redirect_to newsletter_redirect_target,
                    notice: "Danke! Du bist jetzt für den Newsletter eingetragen."
      end
    end

    def respond_to_error(subscriber)
      if newsletter_frame_request?
        render_signup(subscriber:, subscribed: false, status: :unprocessable_entity)
      else
        redirect_to newsletter_redirect_target,
                    alert: subscriber.errors.full_messages.to_sentence
      end
    end

    def render_signup(subscriber:, subscribed:, status:)
      render partial: "public/newsletter_subscribers/signup",
             locals: { subscriber:, signup: newsletter_signup, subscribed: },
             status:
    end
  end
end
