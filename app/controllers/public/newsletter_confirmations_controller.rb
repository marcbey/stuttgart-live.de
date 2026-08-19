module Public
  class NewsletterConfirmationsController < ApplicationController
    allow_unauthenticated_access

    def show
      subscriber = NewsletterSubscriber.find_signed!(
        params[:token],
        purpose: NewsletterSubscriber::CONFIRMATION_TOKEN_PURPOSE
      )
      subscriber.confirm!

      @subscriber = subscriber
      @confirmed = true
      render :show
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      @confirmed = false
      render :show, status: :unprocessable_entity
    end
  end
end
