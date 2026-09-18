class NewsletterMailer < ApplicationMailer
  before_action :disable_tracking

  def confirmation(subscriber)
    @subscriber = subscriber
    @confirmation_url = newsletter_confirmation_url(subscriber.confirmation_token)

    mail subject: Newsletter::ConsentText::CONFIRMATION_SUBJECT, to: subscriber.email
  end

  def preferences(subscriber)
    @preferences_url = newsletter_preferences_url(token: subscriber.preferences_token)
    mail subject: "Ihre Tracking-Einstellungen für den StuttgartLIVE-Newsletter", to: subscriber.email
  end

  private

  def disable_tracking
    headers["X-Mailjet-TrackOpen"] = "0"
    headers["X-Mailjet-TrackClick"] = "0"
  end
end
