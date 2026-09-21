module Public
  class NewsletterPreferencesController < ApplicationController
    allow_unauthenticated_access
    layout "newsletter"
    before_action :prevent_caching
    before_action :find_subscriber, only: [ :show, :update ], if: -> { params[:token].present? || action_name == "update" }
    rate_limit to: 5, within: 10.minutes, only: :create,
               with: -> { redirect_to newsletter_preferences_path, alert: "Bitte versuchen Sie es später erneut." }

    def show
    end

    def create
      subscriber = NewsletterSubscriber.confirmed.find_by_normalized_email(params[:email])
      Newsletter::SendPreferencesEmailJob.perform_later(subscriber) if subscriber
      redirect_to newsletter_preferences_path, notice: "Wenn für diese E-Mail-Adresse eine bestätigte Anmeldung vorliegt, erhalten Sie einen Link zu Ihren Tracking-Einstellungen."
    end

    def update
      @subscriber.update_tracking_consent!(params.require(:tracking_consent))
      redirect_to newsletter_preferences_path(token: params[:token]), notice: "Ihre Tracking-Einstellung wurde gespeichert. Ihr Newsletter-Abonnement bleibt unverändert."
    end

    private

    def prevent_caching
      response.headers["Cache-Control"] = "no-store"
      response.headers["Referrer-Policy"] = "same-origin"
    end

    def find_subscriber
      @subscriber = NewsletterSubscriber.confirmed.find_by_token_for!(:newsletter_preferences, params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      @invalid_token = true
      render :show, status: :unprocessable_entity
    end
  end
end
