module Public
  class NewsletterConfirmationsController < ApplicationController
    allow_unauthenticated_access
    layout "newsletter"
    before_action -> { response.headers["Cache-Control"] = "no-store" }

    def show
      subscriber = NewsletterSubscriber.find_by_token_for!(:newsletter_confirmation, params[:token])
      raise ActiveRecord::RecordNotFound unless subscriber.confirm!(token: params[:token])

      @subscriber = subscriber
      @confirmed = true
      render :show
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      @confirmed = false
      render :show, status: :unprocessable_entity
    end
  end
end
