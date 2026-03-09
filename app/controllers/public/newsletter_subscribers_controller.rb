module Public
  class NewsletterSubscribersController < ApplicationController
    allow_unauthenticated_access only: [ :create ]

    def create
      subscriber = NewsletterSubscriber.new(newsletter_subscriber_params.merge(source: "homepage"))

      if subscriber.save
        redirect_to events_path(filter: params[:filter].presence, view: params[:view].presence, q: params[:q].presence),
                    notice: "Danke. Du bist jetzt fuer den Newsletter eingetragen."
      else
        redirect_to events_path(filter: params[:filter].presence, view: params[:view].presence, q: params[:q].presence),
                    alert: subscriber.errors.full_messages.to_sentence
      end
    end

    private

    def newsletter_subscriber_params
      params.require(:newsletter_subscriber).permit(:email)
    end
  end
end
