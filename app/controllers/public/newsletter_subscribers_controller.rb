module Public
  class NewsletterSubscribersController < ApplicationController
    allow_unauthenticated_access only: [ :create ]

    def create
      subscriber = NewsletterSubscriber.new(newsletter_subscriber_params.merge(source: newsletter_source))

      if subscriber.save
        redirect_to newsletter_redirect_target,
                    notice: "Danke. Du bist jetzt fuer den Newsletter eingetragen."
      else
        redirect_to newsletter_redirect_target,
                    alert: subscriber.errors.full_messages.to_sentence
      end
    end

    private

    def newsletter_subscriber_params
      params.require(:newsletter_subscriber).permit(:email)
    end

    def newsletter_redirect_target
      params[:return_to].presence || events_path(filter: params[:filter].presence, view: params[:view].presence, q: params[:q].presence)
    end

    def newsletter_source
      params[:source].presence || "homepage"
    end
  end
end
